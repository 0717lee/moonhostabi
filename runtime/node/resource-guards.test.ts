import assert from "node:assert/strict";
import { assertTableContract } from "./table-guard.js";
import { assertGlobalContract } from "./global-guard.js";
import { assertTagContract } from "./tag-guard.js";

const table = new WebAssembly.Table({ element: "externref", initial: 2 });
assert.equal(assertTableContract({ table }, {
  schemaVersion: 1, kind: "table", exportName: "table", element: "externref", minimumLength: 2,
}), table);
assert.throws(() => assertTableContract({ table }, {
  schemaVersion: 1, kind: "table", exportName: "table", element: "externref", minimumLength: 3,
}), /MHA_ADAPTER_MISMATCH/);

const global = new WebAssembly.Global({ value: "i32", mutable: false }, 42);
assert.equal(assertGlobalContract({ global }, {
  schemaVersion: 1, kind: "global", exportName: "global", valueType: "i32", mutable: false,
}), global);
assert.throws(() => assertGlobalContract(Object.create({ global }), {
  schemaVersion: 1, kind: "global", exportName: "global", valueType: "i32",
}), /MHA_ADAPTER_MISMATCH/);

const tag = typeof WebAssembly.Tag === "function" ? new WebAssembly.Tag({ parameters: ["i32"] }) : undefined;
if (tag !== undefined) {
  assert.equal(assertTagContract({ tag }, {
    schemaVersion: 1, kind: "tag", exportName: "tag", minimumParameters: 1,
  }), tag);
  assert.throws(() => assertTagContract({ tag }, { schemaVersion: 1, kind: "tag", exportName: "tag", minimumParameters: -1 }), /MHA_ADAPTER_MISMATCH/);
}

console.log("table/global/tag contract guards: ok");
