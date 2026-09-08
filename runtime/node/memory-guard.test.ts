import assert from "node:assert/strict";
import { assertMemoryContract, type MemoryContract } from "./memory-guard.js";

const contract: MemoryContract = {
  schemaVersion: 1,
  kind: "memory",
  exportName: "memory",
  minimumPages: 1,
  shared: false,
};

const memory = new WebAssembly.Memory({ initial: 1, maximum: 2 });
assert.equal(assertMemoryContract({ memory }, contract), memory);

assert.throws(
  () => assertMemoryContract({}, contract),
  /MHA_ADAPTER_MISMATCH: module export exports\[memory\] must be a WebAssembly.Memory/,
);
assert.throws(
  () => assertMemoryContract({ memory: 1 }, contract),
  /MHA_ADAPTER_MISMATCH: module export exports\[memory\] must be a WebAssembly.Memory/,
);
assert.throws(
  () =>
    assertMemoryContract({ memory }, { ...contract, minimumPages: 2 }),
  /MHA_ADAPTER_MISMATCH: memory exports\[memory\] has 1 pages; expected at least 2/,
);
assert.throws(
  () =>
    assertMemoryContract({ memory }, { ...contract, minimumPages: -1 }),
  /MHA_ADAPTER_MISMATCH: invalid memory contract/,
);
for (const invalid of [
  null,
  undefined,
  1,
  "memory",
  {},
  { ...contract, maximumPages: 2 },
]) {
  assert.throws(
    () => assertMemoryContract({ memory }, invalid),
    /MHA_ADAPTER_MISMATCH: invalid memory contract/,
  );
}
assert.throws(
  () => assertMemoryContract(null, contract),
  /MHA_ADAPTER_MISMATCH: module export exports\[memory\] must be a WebAssembly.Memory/,
);
assert.throws(
  () => assertMemoryContract(Object.create({ memory }), contract),
  /MHA_ADAPTER_MISMATCH: module export exports\[memory\] must be a WebAssembly.Memory/,
);

console.log("memory contract guard: ok");
