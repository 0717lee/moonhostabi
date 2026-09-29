import { fileURLToPath } from "node:url";

import { defineConfig } from "playwright/test";

export default defineConfig({
  testDir: ".",
  testMatch: "resources.spec.ts",
  outputDir: "../../_build/resource-browser-results",
  fullyParallel: false,
  workers: 1,
  reporter: "list",
  timeout: 30_000,
  use: {
    baseURL: "http://127.0.0.1:4174",
    browserName: "chromium",
    trace: "retain-on-failure",
  },
  webServer: {
    command: "node browser/server.mjs --resources",
    cwd: fileURLToPath(new URL("..", import.meta.url)),
    url: "http://127.0.0.1:4174/",
    reuseExistingServer: false,
    timeout: 10_000,
  },
});
