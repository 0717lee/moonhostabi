///|
fn resource_contract_runtime() -> String {
  (
    #|type ResourceBinding = {
    #|  readonly path: string;
    #|  readonly module: string | null;
    #|  readonly name: string;
    #|  readonly kind: "memory" | "table" | "global" | "tag";
    #|  readonly probe: readonly number[];
    #|};
    #|
    #|async function verifyResourceArtifact(bytes: BufferSource): Promise<Uint8Array<ArrayBuffer>> {
    #|  if (!(bytes instanceof ArrayBuffer) && !ArrayBuffer.isView(bytes)) {
    #|    throw new Error("MHA_ADAPTER_MISMATCH: resources require artifact bytes");
    #|  }
    #|  const source = bytes instanceof ArrayBuffer
    #|    ? new Uint8Array(bytes)
    #|    : new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    #|  const snapshot = new Uint8Array(source);
    #|  if (!globalThis.crypto?.subtle) {
    #|    throw new Error("MHA_ADAPTER_MISMATCH: resource artifact verification requires Web Crypto SHA-256");
    #|  }
    #|  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", snapshot));
    #|  const actual = Array.from(digest, byte => byte.toString(16).padStart(2, "0")).join("");
    #|  if (actual !== resourceArtifactSha256) {
    #|    throw new Error("MHA_ADAPTER_MISMATCH: resource artifact SHA-256 does not match; regenerate the adapter for these bytes");
    #|  }
    #|  return snapshot;
    #|}
    #|
    #|function snapshotResourceImports<T extends object>(root: T): T {
    #|  if (typeof root !== "object" || root === null) {
    #|    throw new Error("MHA_ADAPTER_MISMATCH: host imports must be an object");
    #|  }
    #|  const snapshot: Record<string, Record<string, unknown>> = Object.create(null);
    #|  const modules = new Map<string, Record<string, unknown>>();
    #|  for (const key of resourceImportKeys) {
    #|    let source = modules.get(key.module);
    #|    if (source === undefined) {
    #|      if (!Object.prototype.hasOwnProperty.call(root, key.module)) {
    #|        throw new Error(`MHA_ADAPTER_MISMATCH: missing import module ${key.module}`);
    #|      }
    #|      const value = (root as Record<string, unknown>)[key.module];
    #|      if (typeof value !== "object" || value === null) {
    #|        throw new Error(`MHA_ADAPTER_MISMATCH: invalid import module ${key.module}`);
    #|      }
    #|      source = value as Record<string, unknown>;
    #|      modules.set(key.module, source);
    #|      snapshot[key.module] = Object.create(null);
    #|    }
    #|    if (!Object.prototype.hasOwnProperty.call(source, key.name)) {
    #|      throw new Error(`MHA_ADAPTER_MISMATCH: missing host import ${key.module}.${key.name}`);
    #|    }
    #|    snapshot[key.module][key.name] = source[key.name];
    #|  }
    #|  // The exact required keys are copied once; the following function and
    #|  // resource checks validate these values before the same snapshot is used.
    #|  return snapshot as T;
    #|}
    #|
    #|function assertResourceBindings(root: unknown, imports: boolean): void {
    #|  for (const contract of resourceContracts) {
    #|    if ((contract.module !== null) !== imports) continue;
    #|    let container = root;
    #|    if (contract.module !== null) {
    #|      if (typeof container !== "object" || container === null ||
    #|          !Object.prototype.hasOwnProperty.call(container, contract.module)) {
    #|        throw new Error(`MHA_ADAPTER_MISMATCH: missing resource ${contract.path}`);
    #|      }
    #|      container = (container as Record<string, unknown>)[contract.module];
    #|    }
    #|    if (typeof container !== "object" || container === null ||
    #|        !Object.prototype.hasOwnProperty.call(container, contract.name)) {
    #|      throw new Error(`MHA_ADAPTER_MISMATCH: missing resource ${contract.path}`);
    #|    }
    #|    const value = (container as Record<string, unknown>)[contract.name];
    #|    const validInstance = contract.kind === "memory" ? value instanceof WebAssembly.Memory
    #|      : contract.kind === "table" ? value instanceof WebAssembly.Table
    #|      : contract.kind === "global" ? value instanceof WebAssembly.Global
    #|      : typeof WebAssembly.Tag === "function" && value instanceof WebAssembly.Tag;
    #|    if (!validInstance) {
    #|      throw new Error(`MHA_ADAPTER_MISMATCH: ${contract.path} must be a WebAssembly ${contract.kind}`);
    #|    }
    #|    // A module containing only this import checks limits, reference types,
    #|    // global mutability and tag signatures without executing artifact code.
    #|    try {
    #|      const probe = new WebAssembly.Module(new Uint8Array(contract.probe));
    #|      new WebAssembly.Instance(probe, { "": { value: value as WebAssembly.ImportValue } });
    #|    } catch (cause) {
    #|      throw new Error(`MHA_ADAPTER_MISMATCH: ${contract.path} resource type or limits do not match`, { cause });
    #|    }
    #|  }
    #|}
    #|
  )
}
