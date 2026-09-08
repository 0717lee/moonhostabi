export interface TagContract {
  schemaVersion: 1;
  kind: "tag";
  exportName: string;
  minimumParameters?: number;
}

function fail(message: string): never {
  throw new Error(`MHA_ADAPTER_MISMATCH: ${message}`);
}

export function assertTagContract(exports: unknown, contract: unknown): WebAssembly.Tag {
  if (typeof contract !== "object" || contract === null) fail("invalid tag contract");
  const c = contract as Record<string, unknown>;
  const allowed = ["schemaVersion", "kind", "exportName", "minimumParameters"];
  if (
    Object.keys(c).some((key) => !allowed.includes(key)) ||
    !["schemaVersion", "kind", "exportName"].every((key) =>
      Object.prototype.hasOwnProperty.call(c, key),
    ) ||
    c.schemaVersion !== 1 || c.kind !== "tag" ||
    typeof c.exportName !== "string" || c.exportName.length === 0 ||
    (c.minimumParameters !== undefined &&
      (typeof c.minimumParameters !== "number" || !Number.isInteger(c.minimumParameters) || c.minimumParameters < 0))
  ) fail("invalid tag contract");
  if (typeof exports !== "object" || exports === null ||
      !Object.prototype.hasOwnProperty.call(exports, c.exportName)) {
    fail(`module export exports[${c.exportName}] must be a WebAssembly.Tag`);
  }
  const tag = (exports as Record<string, unknown>)[c.exportName];
  if (typeof WebAssembly.Tag !== "function" || !(tag instanceof WebAssembly.Tag)) {
    fail(`module export exports[${c.exportName}] must be a WebAssembly.Tag`);
  }
  return tag;
}
