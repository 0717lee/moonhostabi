/** Runtime validation for the memory part of a Host ABI contract. */

export interface MemoryContract {
  schemaVersion: 1;
  kind: "memory";
  exportName: string;
  minimumPages: number;
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
  exports: unknown,
  contract: unknown,
): WebAssembly.Memory {
  if (typeof contract !== "object" || contract === null) {
    throw mismatch("invalid memory contract");
  }
  const shape = contract as Record<string, unknown>;
  const allowedKeys = [
    "schemaVersion",
    "kind",
    "exportName",
    "minimumPages",
    "shared",
  ];
  const { schemaVersion, kind, exportName, minimumPages, shared } = shape;
  if (
    Object.keys(shape).some((key) => !allowedKeys.includes(key)) ||
    !["schemaVersion", "kind", "exportName", "minimumPages"].every((key) =>
      Object.prototype.hasOwnProperty.call(shape, key),
    ) ||
    schemaVersion !== 1 ||
    kind !== "memory" ||
    typeof exportName !== "string" ||
    exportName.length === 0 ||
    typeof minimumPages !== "number" ||
    !Number.isInteger(minimumPages) ||
    minimumPages < 0 ||
    (shared !== undefined && typeof shared !== "boolean")
  ) {
    throw mismatch("invalid memory contract");
  }

  const resourceError = `module export exports[${exportName}] must be a WebAssembly.Memory`;
  if (
    typeof exports !== "object" ||
    exports === null ||
    !Object.prototype.hasOwnProperty.call(exports, exportName)
  ) {
    throw mismatch(resourceError);
  }
  const value = (exports as Record<string, unknown>)[exportName];
  if (!(value instanceof WebAssembly.Memory)) {
    throw mismatch(resourceError);
  }

  const pages = value.buffer.byteLength / 65536;
  if (pages < minimumPages) {
    throw mismatch(
      `memory exports[${exportName}] has ${pages} pages; expected at least ${minimumPages}`,
    );
  }

  if (shared !== undefined) {
    const isShared =
      typeof SharedArrayBuffer !== "undefined" &&
      value.buffer instanceof SharedArrayBuffer;
    if (isShared !== shared) {
      throw mismatch(
        `memory exports[${exportName}] shared flag does not match contract`,
      );
    }
  }

  return value;
}
