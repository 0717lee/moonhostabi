import { expect, test } from "playwright/test";

import { resourceScenarioNames } from "./resources-helper.mjs";

test("resource server exposes only explicit generated adapters and fixtures", async ({ request }) => {
  const html = await request.get("/");
  expect(html.status()).toBe(200);
  expect(html.headers()["content-type"]).toBe("text/html; charset=utf-8");
  for (const name of ["resources", "resources-imports", "resources-escaped"]) {
    const adapter = await request.get(`/generated/${name}/adapter.js`);
    expect(adapter.status()).toBe(200);
    expect(adapter.headers()["content-type"]).toBe("text/javascript; charset=utf-8");
    const wasm = await request.get(`/fixtures/${name}.wasm`);
    expect(wasm.status()).toBe(200);
    expect(wasm.headers()["content-type"]).toBe("application/wasm");
    expect(WebAssembly.validate(new Uint8Array(await wasm.body()))).toBe(true);
  }
  for (const path of [
    "/package.json",
    "/generated/package.json",
    "/generated/resources/adapter.ts",
    "/generated/resources/moonhostabi.contract.json",
    "/generated/resources/../package.json",
    "/%2e%2e/package.json",
    "/generated/resources/%2e%2e%2fpackage.json",
    "/fixtures/resources-table-type-changed.wasm",
    "/fixtures/artifacts/externref.wasm",
    "/dist/generated/adapter.js",
  ]) {
    expect((await request.get(path)).status(), path).toBe(404);
  }
  const head = await request.head("/generated/resources/adapter.js");
  expect(head.status()).toBe(200);
  expect((await head.body()).byteLength).toBe(0);
  const post = await request.post("/");
  expect(post.status()).toBe(405);
  expect(post.headers().allow).toBe("GET, HEAD");
});

for (const name of resourceScenarioNames) {
  test(`Chromium resources: ${name}`, async ({ page }) => {
    const failures: string[] = [];
    page.on("pageerror", (error) => failures.push(error.message));
    page.on("console", (message) => {
      if (message.type() === "error") failures.push(message.text());
    });
    await page.goto("/");
    const completed = await page.evaluate(async (scenario) => {
      if (!globalThis.isSecureContext || !globalThis.crypto?.subtle) {
        throw new Error("Resource verification requires a secure loopback Web Crypto context");
      }
      const helperUrl = "/resources-helper.mjs";
      const { runResourceScenario } = await import(helperUrl);
      await runResourceScenario(scenario);
      return scenario;
    }, name);
    expect(completed).toBe(name);
    expect(failures).toEqual([]);
  });
}
