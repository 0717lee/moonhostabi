import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { createHostImports, instantiate } from "./generated/adapter.js";

const [artifactPath, reportPath] = process.argv.slice(2);
assert.ok(artifactPath && reportPath, "expected artifact and SDK report paths");
const bytes = new Uint8Array(readFileSync(artifactPath));
const report = JSON.parse(readFileSync(reportPath, "utf8"));
assert.equal(report.schemaVersion, 1);
assert.equal(report.artifact.status, "valid");
assert.equal(report.artifact.sha256, createHash("sha256").update(bytes).digest("hex"));

// Release policy runs before the generated adapter can instantiate an upgrade.
if (report.outcome !== "compatible") {
  assert.equal(report.outcome, "breaking");
  assert.ok(report.compatibility.changes.some(
    (change: { code: string; path: string }) =>
      change.code === "MHA_SIGNATURE_CHANGED" &&
      change.path === "exports[total_price].params",
  ));
  console.log("CONSUMER_HOST_BLOCKED=breaking");
  process.exitCode = 2;
} else {
  const pricing = await instantiate(bytes, createHostImports());
  // Three items at 1,250 cents, with a 10% discount (1,000 basis points).
  const total = pricing.total_price(1250, 3, 1000);
  assert.equal(total, 3375);
  assert.equal(pricing.total_price(1250, 0, 1000), 0);
  assert.equal(pricing.total_price(1250, 3, 0), 3750);
  console.log(`CONSUMER_HOST_TOTAL_CENTS=${total}`);
}
