import { readFile } from "node:fs/promises";

import {
  instantiate,
  type HostImports,
} from "../generated/adapter.js";

type HostToken = {
  readonly marker: "moonhostabi-negative-token";
};

function invariant(condition: boolean, message: string): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

const artifactUrl = new URL(
  "../../../fixtures/artifacts/externref.wasm",
  import.meta.url,
);
const fileBytes = await readFile(artifactUrl);
const bytes = Uint8Array.from(fileBytes);
const missingEcho = { host: {} } as unknown as HostImports<HostToken>;

let observed: Error | undefined;
try {
  await instantiate(bytes, missingEcho);
} catch (error) {
  observed = error instanceof Error ? error : new Error(String(error));
}

invariant(observed !== undefined, "expected missing host.echo to be rejected");
invariant(
  observed.message.includes("MHA_ADAPTER_MISMATCH"),
  `expected MHA_ADAPTER_MISMATCH, received: ${observed.message}`,
);
invariant(
  observed.message.includes("imports[host.echo]"),
  `expected imports[host.echo] path, received: ${observed.message}`,
);

console.log(
  JSON.stringify({
    code: "MHA_ADAPTER_MISMATCH",
    path: "imports[host.echo]",
    observed: true,
  }),
);
