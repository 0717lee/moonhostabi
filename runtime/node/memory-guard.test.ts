import assert from "node:assert/strict";
import { assertMemoryContract, type MemoryContract } from "./memory-guard.js";

const contract: MemoryContract = {
  schemaVersion: 1,
  kind: "memory",
  exportName: "memory",
  minimumPages: 1,
  maximumPages: 2,
  shared: false,
};

const memory = new WebAssembly.Memory({ initial: 1, maximum: 2 });
assert.equal(assertMemoryContract({ memory }, contract), memory);

assert.throws(
  () => assertMemoryContract({}, contract),
  /MHA_ADAPTER_MISMATCH: module export exports\[memory\] must be a WebAssembly.Memory/,
);
assert.throws(
  () => assertMemoryContract({ memory: 1 } as unknown as WebAssembly.Exports, contract),
  /MHA_ADAPTER_MISMATCH: module export exports\[memory\] must be a WebAssembly.Memory/,
);
assert.throws(
  () =>
    assertMemoryContract({ memory }, { ...contract, minimumPages: 2 }),
  /MHA_ADAPTER_MISMATCH: memory exports\[memory\] has 1 pages; expected at least 2/,
);
assert.throws(
  () =>
    assertMemoryContract({ memory }, { ...contract, maximumPages: 0 }),
  /MHA_ADAPTER_MISMATCH: invalid memory contract/,
);

console.log("memory contract guard: ok");
