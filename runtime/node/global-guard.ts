export interface GlobalContract {
  schemaVersion: 1;
  kind: "global";
  exportName: string;
  valueType: "i32" | "i64" | "f32" | "f64" | "externref";
  mutable?: boolean;
}

function fail(message: string): never {
  throw new Error(`MHA_ADAPTER_MISMATCH: ${message}`);
}

export function assertGlobalContract(exports: unknown, contract: unknown): WebAssembly.Global {
  if (typeof contract !== "object" || contract === null) fail("invalid global contract");
  const c = contract as Record<string, unknown>;
  const allowed = ["schemaVersion", "kind", "exportName", "valueType", "mutable"];
  if (
    Object.keys(c).some((key) => !allowed.includes(key)) ||
    !["schemaVersion", "kind", "exportName", "valueType"].every((key) =>
      Object.prototype.hasOwnProperty.call(c, key),
    ) ||
    c.schemaVersion !== 1 || c.kind !== "global" ||
    typeof c.exportName !== "string" || c.exportName.length === 0 ||
    !["i32", "i64", "f32", "f64", "externref"].includes(c.valueType as string) ||
    (c.mutable !== undefined && typeof c.mutable !== "boolean")
  ) fail("invalid global contract");
  if (typeof exports !== "object" || exports === null ||
      !Object.prototype.hasOwnProperty.call(exports, c.exportName)) {
    fail(`module export exports[${c.exportName}] must be a WebAssembly.Global`);
  }
  const global = (exports as Record<string, unknown>)[c.exportName];
  if (!(global instanceof WebAssembly.Global)) {
    fail(`module export exports[${c.exportName}] must be a WebAssembly.Global`);
  }
  const value = global.value;
  const validType = c.valueType === "i64" ? typeof value === "bigint" :
    c.valueType === "externref" ? true : typeof value === "number";
  if (!validType) fail(`global exports[${c.exportName}] value type does not match contract`);
  const mutable = (global as unknown as { mutable?: unknown }).mutable;
  if (c.mutable !== undefined && mutable !== undefined && mutable !== c.mutable) {
    fail(`global exports[${c.exportName}] mutable flag does not match contract`);
  }
  return global;
}
