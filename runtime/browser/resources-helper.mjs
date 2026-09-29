function equal(actual, expected, label) {
  if (actual !== expected) throw new Error(`${label}: expected ${expected}, received ${actual}`);
}

async function adapter(name) {
  return import(`/generated/${name}/adapter.js`);
}

async function bytes(name) {
  const response = await fetch(`/fixtures/${name}.wasm`);
  if (!response.ok) throw new Error(`Fixture ${name}: HTTP ${response.status}`);
  return new Uint8Array(await response.arrayBuffer());
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
  equal(exports.memory instanceof WebAssembly.Memory, true, "memory kind");
  equal(exports.table instanceof WebAssembly.Table, true, "table kind");
  equal(exports.global instanceof WebAssembly.Global, true, "global kind");
  equal(exports.tag instanceof WebAssembly.Tag, true, "tag kind");
  new Uint8Array(exports.memory.buffer)[17] = 91;
  equal(new Uint8Array(exports.memory.buffer)[17], 91, "memory write/read");
  equal(exports.memory.grow(1), 1, "memory growth");
  equal(exports.memory.buffer.byteLength, 2 * 65536, "grown memory size");
  const token = { label: "table identity" };
  exports.table.set(0, token);
  equal(exports.table.get(0), token, "table identity");
  equal(exports.table.grow(1), 2, "table growth");
  equal(exports.table.length, 3, "grown table size");
  equal(exports.global.value, 7, "initial global");
  exports.global.value = 19;
  equal(exports.global.value, 19, "global write/read");
  const exception = new WebAssembly.Exception(exports.tag, [42]);
  equal(exception.is(exports.tag), true, "exception tag identity");
  equal(exception.getArg(exports.tag, 0), 42, "exception payload");
}

async function expectRejectionBeforeApplicationStart(invoke, artifact) {
  const instantiate = WebAssembly.instantiate;
  let applicationInstantiations = 0;
  WebAssembly.instantiate = function (source, imports) {
    // Resource probes are separate tiny modules; only count application bytes.
    const input = source instanceof ArrayBuffer ? new Uint8Array(source)
      : ArrayBuffer.isView(source) ? new Uint8Array(source.buffer, source.byteOffset, source.byteLength)
      : null;
    if (input !== null && input.length === artifact.length &&
        input.every((value, index) => value === artifact[index])) {
      applicationInstantiations += 1;
    }
    return instantiate.call(WebAssembly, source, imports);
  };
  let observed;
  try {
    await invoke();
  } catch (error) {
    observed = error;
  } finally {
    WebAssembly.instantiate = instantiate;
  }
  equal(observed instanceof Error, true, "adapter rejection");
  equal(observed.message.startsWith("MHA_ADAPTER_MISMATCH:"), true, "adapter diagnostic");
  equal(applicationInstantiations, 0, "rejected application must not be instantiated");
}

const scenarios = new Map([
  ["local memory/table/global/tag operations", async () => {
    const local = await adapter("resources");
    exerciseLocalResources(await local.instantiateWithResources(await bytes("resources"), {}));
  }],
  ["imported and reexported resource identity and operations", async () => {
    const imported = await adapter("resources-imports");
    const env = hostResources();
    const exports = await imported.instantiateWithResources(await bytes("resources-imports"), { env });
    for (const kind of ["memory", "table", "global", "tag"]) {
      equal(exports[`imported_${kind}`], env[kind], `${kind} reexport identity`);
    }
    exerciseLocalResources(exports);
    new Uint8Array(env.memory.buffer)[25] = 73;
    equal(exports.read_host_memory(25), 73, "Wasm reads host memory");
    exports.write_host_memory(25, 89);
    equal(new Uint8Array(env.memory.buffer)[25], 89, "Wasm writes host memory");
    equal(exports.read_host_global(), 11, "Wasm reads host global");
    exports.write_host_global(27);
    equal(env.global.value, 27, "Wasm writes host global");
    const token = { label: "host reference" };
    exports.imported_table.set(0, token);
    equal(env.table.get(0), token, "host table identity");
    const exception = new WebAssembly.Exception(exports.imported_tag, [13]);
    equal(exception.is(env.tag), true, "host tag identity");
    equal(exception.getArg(env.tag, 0), 13, "host tag payload");
  }],
  ["resource getters use the validated snapshot once", async () => {
    const imported = await adapter("resources-imports");
    const env = hostResources();
    const resourceReads = new Map();
    const getters = {};
    for (const kind of ["memory", "table", "global", "tag"]) {
      resourceReads.set(kind, 0);
      Object.defineProperty(getters, kind, {
        enumerable: true,
        get() {
          const count = resourceReads.get(kind) + 1;
          resourceReads.set(kind, count);
          return count === 1 ? env[kind] : {};
        },
      });
    }
    let moduleReads = 0;
    const exports = await imported.instantiateWithResources(await bytes("resources-imports"), {
      get env() { return ++moduleReads === 1 ? getters : {}; },
    });
    equal(moduleReads, 1, "module getter reads");
    for (const kind of ["memory", "table", "global", "tag"]) {
      equal(resourceReads.get(kind), 1, `${kind} getter reads`);
      equal(exports[`imported_${kind}`], env[kind], `${kind} snapshot identity`);
    }
  }],
  ["escaped resource export names", async () => {
    const escaped = await adapter("resources-escaped");
    const exports = await escaped.instantiateWithResources(await bytes("resources-escaped"), {});
    const memory = exports['memory"quoted\nname'];
    const table = exports["table\\name"];
    equal(memory instanceof WebAssembly.Memory, true, "escaped memory kind");
    equal(table instanceof WebAssembly.Table, true, "escaped table kind");
    new Uint8Array(memory.buffer)[1] = 61;
    equal(new Uint8Array(memory.buffer)[1], 61, "escaped memory write/read");
    const token = { label: "escaped reference" };
    table.set(0, token);
    equal(table.get(0), token, "escaped table identity");
  }],
]);

const rejectionCases = new Map([
  ["missing module", () => ({})],
  ...["memory", "table", "global", "tag"].map((kind) => [
    `missing ${kind}`, () => {
      const env = hostResources();
      delete env[kind];
      return { env };
    },
  ]),
  ["wrong memory kind", () => ({ env: { ...hostResources(), memory: {} } })],
  ["memory below minimum", () => ({ env: { ...hostResources(), memory: new WebAssembly.Memory({ initial: 0, maximum: 3 }) } })],
  ["memory above maximum", () => ({ env: { ...hostResources(), memory: new WebAssembly.Memory({ initial: 1, maximum: 4 }) } })],
  ["wrong table kind", () => ({ env: { ...hostResources(), table: {} } })],
  ["wrong table element type", () => ({ env: { ...hostResources(), table: new WebAssembly.Table({ element: "anyfunc", initial: 2, maximum: 4 }) } })],
  ["table below minimum", () => ({ env: { ...hostResources(), table: new WebAssembly.Table({ element: "externref", initial: 1, maximum: 4 }) } })],
  ["wrong global kind", () => ({ env: { ...hostResources(), global: 7 } })],
  ["wrong global value type", () => ({ env: { ...hostResources(), global: new WebAssembly.Global({ value: "i64", mutable: true }, 7n) } })],
  ["wrong global mutability", () => ({ env: { ...hostResources(), global: new WebAssembly.Global({ value: "i32", mutable: false }, 7) } })],
  ["wrong tag kind", () => ({ env: { ...hostResources(), tag: {} } })],
  ["wrong tag signature", () => ({ env: { ...hostResources(), tag: new WebAssembly.Tag({ parameters: ["i64"] }) } })],
]);
for (const [label, imports] of rejectionCases) {
  scenarios.set(`rejects ${label} before application start`, async () => {
    const imported = await adapter("resources-imports");
    const artifact = await bytes("resources-imports");
    await expectRejectionBeforeApplicationStart(
      () => imported.instantiateWithResources(artifact, imports()), artifact,
    );
  });
}

for (const entryPoint of ["instantiateWithResources", "instantiate"]) {
  for (const name of ["invalid", "resources-changed"]) {
    scenarios.set(`${entryPoint} rejects ${name} artifact`, async () => {
      const local = await adapter("resources");
      const artifact = name === "invalid" ? new Uint8Array([0, 1, 2]) : await bytes(name);
      await expectRejectionBeforeApplicationStart(() => local[entryPoint](artifact, {}), artifact);
    });
  }
  scenarios.set(`${entryPoint} rejects changed artifact before its start side effect`, async () => {
    const imported = await adapter("resources-imports");
    const artifact = await bytes("resources-imports-start-changed");
    const control = hostResources();
    await WebAssembly.instantiate(artifact, { env: control });
    equal(control.global.value, 666, "control proves the start function runs");
    const env = hostResources();
    await expectRejectionBeforeApplicationStart(() => imported[entryPoint](artifact, { env }), artifact);
    equal(env.global.value, 11, "rejected module start must have no side effect");
  });
}

export const resourceScenarioNames = [...scenarios.keys()];

export async function runResourceScenario(name) {
  const scenario = scenarios.get(name);
  if (scenario === undefined) throw new Error(`Unknown resource scenario: ${name}`);
  await scenario();
}
