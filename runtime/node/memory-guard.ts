/** Runtime validation for the memory part of a Host ABI contract. */

export interface MemoryContract {
  schemaVersion: 1;
  kind: "memory";
  exportName: string;
  minimumPages: number;
  maximumPages?: number;
  shared?: boolean;
}

function mismatch(message: string): Error {
  return new Error(`MHA_ADAPTER_MISMATCH: ${message}`);
}

/**
 * Validate an exported WebAssembly.Memory against an explicit contract.
 *
 * This guard does not generate a binding or infer a maximum from the runtime;
 * it only checks properties observable after instantiation and fails closed on
 * malformed contracts.
 */
export function assertMemoryContract(
  exports: WebAssembly.Exports,
  contract: MemoryContract,
): WebAssembly.Memory {
  if (
    contract.schemaVersion !== 1 ||
    contract.kind !== "memory" ||
    contract.exportName.length === 0 ||
    !Number.isInteger(contract.minimumPages) ||
    contract.minimumPages < 0 ||
    (contract.maximumPages !== undefined &&
      (!Number.isInteger(contract.maximumPages) ||
        contract.maximumPages < contract.minimumPages))
  ) {
    throw mismatch("invalid memory contract");
  }

  const value = (exports as Record<string, unknown>)[contract.exportName];
  if (!(value instanceof WebAssembly.Memory)) {
    throw mismatch(
      `module export exports[${contract.exportName}] must be a WebAssembly.Memory`,
    );
  }

  const pages = value.buffer.byteLength / 65536;
  if (pages < contract.minimumPages) {
    throw mismatch(
      `memory exports[${contract.exportName}] has ${pages} pages; expected at least ${contract.minimumPages}`,
    );
  }

  if (contract.shared !== undefined) {
    const isShared =
      typeof SharedArrayBuffer !== "undefined" &&
      value.buffer instanceof SharedArrayBuffer;
    if (isShared !== contract.shared) {
      throw mismatch(
        `memory exports[${contract.exportName}] shared flag does not match contract`,
      );
    }
  }

  return value;
}
