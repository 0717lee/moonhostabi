export interface TableContract {
  schemaVersion: 1;
  kind: "table";
  exportName: string;
  element: "anyfunc" | "externref";
  minimumLength: number;
}

function fail(message: string): never {
  throw new Error(`MHA_ADAPTER_MISMATCH: ${message}`);
}

export function assertTableContract(exports: unknown, contract: unknown): WebAssembly.Table {
  if (typeof contract !== "object" || contract === null) fail("invalid table contract");
  const c = contract as Record<string, unknown>;
  const allowed = ["schemaVersion", "kind", "exportName", "element", "minimumLength"];
  if (
    Object.keys(c).some((key) => !allowed.includes(key)) ||
    !allowed.every((key) => Object.prototype.hasOwnProperty.call(c, key)) ||
    c.schemaVersion !== 1 || c.kind !== "table" ||
    typeof c.exportName !== "string" || c.exportName.length === 0 ||
    (c.element !== "anyfunc" && c.element !== "externref") ||
    typeof c.minimumLength !== "number" || !Number.isInteger(c.minimumLength) || c.minimumLength < 0
  ) fail("invalid table contract");
  if (typeof exports !== "object" || exports === null ||
      !Object.prototype.hasOwnProperty.call(exports, c.exportName)) {
    fail(`module export exports[${c.exportName}] must be a WebAssembly.Table`);
  }
  const table = (exports as Record<string, unknown>)[c.exportName];
  if (!(table instanceof WebAssembly.Table)) {
    fail(`module export exports[${c.exportName}] must be a WebAssembly.Table`);
  }
  if (table.length < c.minimumLength) {
    fail(`table exports[${c.exportName}] has ${table.length} elements; expected at least ${c.minimumLength}`);
  }
  const actualElement = (table as unknown as { type?: unknown }).type;
  if (actualElement !== undefined && actualElement !== c.element) {
    fail(`table exports[${c.exportName}] element type does not match contract`);
  }
  return table;
}
