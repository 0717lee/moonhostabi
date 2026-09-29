import { readFile, realpath } from "node:fs/promises";
import { createServer } from "node:http";
import { dirname, isAbsolute, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const browserDirectory = dirname(fileURLToPath(import.meta.url));
const runtimeDirectory = resolve(browserDirectory, "..");
const repositoryDirectory = resolve(runtimeDirectory, "..");
const resourceMode = process.argv.includes("--resources");
const port = resourceMode ? 4174 : 4173;

const assets = new Map(resourceMode ? [] : [
  [
    "/",
    {
      path: resolve(browserDirectory, "index.html"),
      contentType: "text/html; charset=utf-8",
    },
  ],
  [
    "/index.html",
    {
      path: resolve(browserDirectory, "index.html"),
      contentType: "text/html; charset=utf-8",
    },
  ],
  [
    "/dist/generated/adapter.js",
    {
      path: resolve(runtimeDirectory, "dist", "generated", "adapter.js"),
      contentType: "text/javascript; charset=utf-8",
    },
  ],
  [
    "/fixtures/artifacts/externref.wasm",
    {
      path: resolve(
        repositoryDirectory,
        "fixtures",
        "artifacts",
        "externref.wasm",
      ),
      contentType: "application/wasm",
    },
  ],
]);

if (resourceMode) {
  const generatedDirectory = process.env.MOONHOSTABI_RESOURCE_GENERATED_DIR;
  const fixtureDirectory = process.env.MOONHOSTABI_RESOURCE_FIXTURE_DIR;
  if (!generatedDirectory || !fixtureDirectory ||
      !isAbsolute(generatedDirectory) || !isAbsolute(fixtureDirectory)) {
    throw new Error("Resource verification requires absolute MOONHOSTABI_RESOURCE_GENERATED_DIR and MOONHOSTABI_RESOURCE_FIXTURE_DIR paths");
  }
  const generatedRoot = await realpath(generatedDirectory);
  const fixtureRoot = await realpath(fixtureDirectory);
  assets.set("/", {
    body: Buffer.from('<!doctype html><html lang="en"><head><meta charset="utf-8"><title>MoonHostABI resource verification</title><link rel="icon" href="data:,"></head><body></body></html>'),
    contentType: "text/html; charset=utf-8",
  });
  assets.set("/resources-helper.mjs", {
    path: resolve(browserDirectory, "resources-helper.mjs"),
    contentType: "text/javascript; charset=utf-8",
  });
  for (const name of ["resources", "resources-imports", "resources-escaped"]) {
    assets.set(`/generated/${name}/adapter.js`, {
      path: resolve(generatedRoot, name, "adapter.js"),
      contentType: "text/javascript; charset=utf-8",
    });
  }
  for (const name of ["resources", "resources-imports", "resources-escaped", "resources-changed", "resources-imports-start-changed"]) {
    assets.set(`/fixtures/${name}.wasm`, {
      path: resolve(fixtureRoot, `${name}.wasm`),
      contentType: "application/wasm",
    });
  }
}

function sendText(response, status, message, extraHeaders = {}) {
  const body = Buffer.from(message, "utf8");
  response.writeHead(status, {
    "Content-Type": "text/plain; charset=utf-8",
    "Content-Length": String(body.byteLength),
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    ...extraHeaders,
  });
  response.end(body);
}

const server = createServer(async (request, response) => {
  try {
    if (request.method !== "GET" && request.method !== "HEAD") {
      sendText(response, 405, "Method not allowed", { Allow: "GET, HEAD" });
      return;
    }
    const requestUrl = new URL(request.url ?? "/", "http://127.0.0.1");
    const asset = assets.get(requestUrl.pathname);
    if (asset === undefined) {
      sendText(response, 404, "Not found");
      return;
    }
    const body = asset.body ?? await readFile(asset.path);
    response.writeHead(200, {
      "Content-Type": asset.contentType,
      "Content-Length": String(body.byteLength),
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    });
    response.end(request.method === "HEAD" ? undefined : body);
  } catch {
    sendText(response, 500, "Asset unavailable");
  }
});

server.listen(port, "127.0.0.1", () => {
  console.log(`MoonHostABI browser verifier listening on http://127.0.0.1:${port}`);
});

function shutdown() {
  server.close(() => process.exit(0));
}

process.once("SIGINT", shutdown);
process.once("SIGTERM", shutdown);
