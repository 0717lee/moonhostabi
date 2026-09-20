import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [compiledRoot, fixtureRoot] = process.argv.slice(2);
assert.ok(compiledRoot && fixtureRoot, "usage: resource-adapter-e2e.mjs <compiled> <fixtures>");

async function adapter(name) {
  return import(pathToFileURL(join(compiledRoot, name, "adapter.js")).href);
}

async function bytes(name) {
  return new Uint8Array(await readFile(join(fixtureRoot, `${name}.wasm`)));
}

function hostResources() {
  return {
    memory: new WebAssembly.Memory({ initial: 1, maximum: 3 }),
    table: new WebAssembly.Table({ element: "externref", initial: 2, maximum: 4 }),
    global: new WebAssembly.Global({ value: "i32", mutable: true }, 11),
    tag: new WebAssembly.Tag({ parameters: ["i32"] }),
  };
}

function exerciseLocalResources(exports) {
  assert.ok(exports.memory instanceof WebAssembly.Memory);
  assert.ok(exports.table instanceof WebAssembly.Table);
  assert.ok(exports.global instanceof WebAssembly.Global);
  assert.ok(exports.tag instanceof WebAssembly.Tag);
  const view = new Uint8Array(exports.memory.buffer);
  view[17] = 91;
  assert.equal(new Uint8Array(exports.memory.buffer)[17], 91);
  assert.equal(exports.memory.grow(1), 1);
  assert.equal(exports.memory.buffer.byteLength, 2 * 65536);
  const token = { label: "table identity" };
  exports.table.set(0, token);
  assert.equal(exports.table.get(0), token);
  assert.equal(exports.table.grow(1), 2);
  assert.equal(exports.global.value, 7);
  exports.global.value = 19;
  assert.equal(exports.global.value, 19);
  const exception = new WebAssembly.Exception(exports.tag, [42]);
  assert.equal(exception.is(exports.tag), true);
  assert.equal(exception.getArg(exports.tag, 0), 42);
}

const local = await adapter("resources");
const localBytes = await bytes("resources");
const bytesChanged = await bytes("resources-changed");
exerciseLocalResources(await local.instantiateWithResources(localBytes, {}));
await assert.rejects(
  () => local.instantiateWithResources(new Uint8Array([0, 1, 2]), {}),
  /MHA_ADAPTER_MISMATCH/,
  "invalid artifact must be rejected",
);
await assert.rejects(
  () => local.instantiateWithResources(bytesChanged, {}),
  /MHA_ADAPTER_MISMATCH/,
  "an adapter must reject different artifact bytes",
);
await assert.rejects(
  () => local.instantiate(bytesChanged, {}),
  /MHA_ADAPTER_MISMATCH/,
  "the default instantiate entry point must enforce the same artifact contract",
);

const imported = await adapter("resources-imports");
const importedBytes = await bytes("resources-imports");
const env = hostResources();
const exports = await imported.instantiateWithResources(importedBytes, { env });
for (const kind of ["memory", "table", "global", "tag"]) {
  assert.equal(exports[`imported_${kind}`], env[kind], `${kind} re-export identity`);
}
exerciseLocalResources(exports);
new Uint8Array(env.memory.buffer)[25] = 73;
assert.equal(exports.read_host_memory(25), 73);
exports.write_host_memory(25, 89);
assert.equal(new Uint8Array(env.memory.buffer)[25], 89);
assert.equal(exports.read_host_global(), 11);
exports.write_host_global(27);
assert.equal(env.global.value, 27);
const hostToken = { label: "host reference" };
exports.imported_table.set(0, hostToken);
assert.equal(env.table.get(0), hostToken);
const hostException = new WebAssembly.Exception(exports.imported_tag, [13]);
assert.equal(hostException.is(env.tag), true);
assert.equal(hostException.getArg(env.tag, 0), 13);

const getterHost = hostResources();
const getterResources = {};
const resourceReads = new Map();
for (const kind of ["memory", "table", "global", "tag"]) {
  resourceReads.set(kind, 0);
  Object.defineProperty(getterResources, kind, {
    enumerable: true,
    get() {
      const count = resourceReads.get(kind) + 1;
      resourceReads.set(kind, count);
      return count === 1 ? getterHost[kind] : {};
    },
  });
}
let moduleReads = 0;
const getterExports = await imported.instantiateWithResources(importedBytes, {
  get env() {
    moduleReads += 1;
    return moduleReads === 1 ? getterResources : {};
  },
});
assert.equal(moduleReads, 1, "module getter must be read once");
for (const kind of ["memory", "table", "global", "tag"]) {
  assert.equal(resourceReads.get(kind), 1, `${kind} getter must be read once`);
  assert.equal(getterExports[`imported_${kind}`], getterHost[kind], `${kind} must use its validated snapshot`);
}

const rejectionCases = [
  ["missing module", {}],
  ...["memory", "table", "global", "tag"].map((kind) => {
    const missing = hostResources();
    delete missing[kind];
    return [`missing ${kind}`, { env: missing }];
  }),
  ["wrong memory kind", { env: { ...hostResources(), memory: {} } }],
  ["memory below minimum", { env: { ...hostResources(), memory: new WebAssembly.Memory({ initial: 0, maximum: 3 }) } }],
  ["memory above maximum", { env: { ...hostResources(), memory: new WebAssembly.Memory({ initial: 1, maximum: 4 }) } }],
  ["wrong table kind", { env: { ...hostResources(), table: {} } }],
  ["wrong table element type", { env: { ...hostResources(), table: new WebAssembly.Table({ element: "anyfunc", initial: 2, maximum: 4 }) } }],
  ["table below minimum", { env: { ...hostResources(), table: new WebAssembly.Table({ element: "externref", initial: 1, maximum: 4 }) } }],
  ["wrong global kind", { env: { ...hostResources(), global: 7 } }],
  ["wrong global value type", { env: { ...hostResources(), global: new WebAssembly.Global({ value: "i64", mutable: true }, 7n) } }],
  ["wrong global mutability", { env: { ...hostResources(), global: new WebAssembly.Global({ value: "i32", mutable: false }, 7) } }],
  ["wrong tag kind", { env: { ...hostResources(), tag: {} } }],
  ["wrong tag signature", { env: { ...hostResources(), tag: new WebAssembly.Tag({ parameters: ["i64"] }) } }],
];
for (const [label, imports] of rejectionCases) {
  await assert.rejects(
    () => imported.instantiateWithResources(importedBytes, imports),
    /MHA_ADAPTER_MISMATCH/,
    label,
  );
}

const startEnv = hostResources();
const startChangedBytes = await bytes("resources-imports-start-changed");
await assert.rejects(
  () => imported.instantiateWithResources(startChangedBytes, { env: startEnv }),
  /MHA_ADAPTER_MISMATCH/,
  "artifact identity must be checked before executing the start function",
);
assert.equal(startEnv.global.value, 11, "rejected module start must have no side effect");

const escaped = await adapter("resources-escaped");
const escapedExports = await escaped.instantiateWithResources(await bytes("resources-escaped"), {});
const escapedMemory = escapedExports['memory"quoted\nname'];
const escapedTable = escapedExports["table\\name"];
assert.ok(escapedMemory instanceof WebAssembly.Memory);
assert.ok(escapedTable instanceof WebAssembly.Table);
new Uint8Array(escapedMemory.buffer)[1] = 61;
assert.equal(new Uint8Array(escapedMemory.buffer)[1], 61);
escapedTable.set(0, hostToken);
assert.equal(escapedTable.get(0), hostToken);

console.log(`resource adapter E2E: real local/imported/re-exported resources, import snapshots and ${rejectionCases.length + 4} rejection cases passed`);
