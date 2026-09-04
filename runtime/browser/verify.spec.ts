import { expect, test } from "playwright/test";

function capturePageFailures(page: import("playwright").Page) {
  const failures: string[] = [];
  page.on("pageerror", (error) => failures.push(`pageerror: ${error.message}`));
  page.on("console", (message) => {
    if (message.type() === "error") {
      failures.push(`console: ${message.text()}`);
    }
  });
  return failures;
}

test("server exposes only the browser verification assets", async ({ request }) => {
  const html = await request.get("/");
  expect(html.status()).toBe(200);
  expect(html.headers()["content-type"]).toBe("text/html; charset=utf-8");

  const adapter = await request.get("/dist/generated/adapter.js");
  expect(adapter.status()).toBe(200);
  expect(adapter.headers()["content-type"]).toBe(
    "text/javascript; charset=utf-8",
  );

  const wasm = await request.get("/fixtures/artifacts/externref.wasm");
  expect(wasm.status()).toBe(200);
  expect(wasm.headers()["content-type"]).toBe("application/wasm");
  expect(WebAssembly.validate(await wasm.body())).toBe(true);

  expect((await request.get("/package.json")).status()).toBe(404);
  expect((await request.get("/%2e%2e/package.json")).status()).toBe(404);
  const post = await request.post("/");
  expect(post.status()).toBe(405);
  expect(post.headers().allow).toBe("GET, HEAD");
});

test("Chromium executes the real scalar and externref paths", async ({ page }) => {
  const failures = capturePageFailures(page);
  await page.goto("/");

  await expect(page.locator("#result")).toHaveText("42");
  await expect(page.locator("#externref-identity")).toHaveText("true");
  await expect(page.locator("#trace")).toHaveText(
    '{"count":1,"argumentIdentity":true}',
  );
  expect(failures).toEqual([]);
});

test("Chromium reports a missing required host import", async ({ page }) => {
  const failures = capturePageFailures(page);
  await page.goto("/?case=negative");

  await expect(page.locator("#error")).toContainText("MHA_ADAPTER_MISMATCH");
  await expect(page.locator("#error")).toContainText("imports[host.echo]");
  expect(failures).toEqual([]);
});
