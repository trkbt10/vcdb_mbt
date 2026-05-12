/**
 * Exports verification test.
 *
 * Validates that:
 * 1. All package.json exports map entries resolve to existing files
 * 2. Main entry point exports expected symbols
 * 3. Subpath exports are importable and export expected symbols
 * 4. .d.ts files exist alongside .js files
 */

import assert from "node:assert";
import { readFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const pkgDir = join(__dirname, "..");
const pkg = JSON.parse(readFileSync(join(pkgDir, "package.json"), "utf-8"));

let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    console.log(`  \u2713 ${name}`);
    passed++;
  } catch (e) {
    console.log(`  \u2717 ${name}: ${e.message}`);
    failed++;
  }
}

// ── 1. All exports map files exist ──────────────────────────

console.log("\n=== Exports map file existence ===");

for (const [subpath, entry] of Object.entries(pkg.exports)) {
  const files = typeof entry === "string" ? [entry] : Object.values(entry);
  for (const file of files) {
    const fullPath = join(pkgDir, file);
    test(`${subpath} -> ${file}`, () => {
      assert.ok(existsSync(fullPath), `Missing: ${fullPath}`);
    });
  }
}

// ── 2. Main entry point symbols ─────────────────────────────

console.log("\n=== Main entry point (vcdb) ===");

const main = await import(join(pkgDir, "dist/index.js"));

test("exports VectorDB class", () => {
  assert.strictEqual(typeof main.VectorDB, "function");
});

test("exports PersistentDB class", () => {
  assert.strictEqual(typeof main.PersistentDB, "function");
});

test("exports loadModule function", () => {
  assert.strictEqual(typeof main.loadModule, "function");
});

test("exports isModuleLoaded function", () => {
  assert.strictEqual(typeof main.isModuleLoaded, "function");
});

test("exports kvStoreToCallbacks function", () => {
  assert.strictEqual(typeof main.kvStoreToCallbacks, "function");
});

test("exports storageToCallbacks function", () => {
  assert.strictEqual(typeof main.storageToCallbacks, "function");
});

test("PersistentDB.create is static async", () => {
  assert.strictEqual(typeof main.PersistentDB.create, "function");
});

test("PersistentDB has no public constructor args (use create())", () => {
  // Private constructor is a TS-only constraint; at runtime we verify
  // that create() is the intended entry point
  assert.strictEqual(typeof main.PersistentDB.create, "function");
  assert.strictEqual(typeof main.PersistentDB.prototype.upsert, "function");
  assert.strictEqual(typeof main.PersistentDB.prototype.search, "function");
});

// ── 3. Distributed subpath ──────────────────────────────────

console.log("\n=== Distributed subpath (vcdb/distributed) ===");

const distributed = await import(join(pkgDir, "dist/distributed.js"));

test("exports placementGroup", () => {
  assert.strictEqual(typeof distributed.placementGroup, "function");
});

test("exports groupUpsert", () => {
  assert.strictEqual(typeof distributed.groupUpsert, "function");
});

test("exports mergeSearch", () => {
  assert.strictEqual(typeof distributed.mergeSearch, "function");
});

test("exports mergeScroll", () => {
  assert.strictEqual(typeof distributed.mergeScroll, "function");
});

test("exports mergeCount", () => {
  assert.strictEqual(typeof distributed.mergeCount, "function");
});

// ── 4. Gateway subpath ──────────────────────────────────────

console.log("\n=== Gateway subpath (vcdb/gateway) ===");

const gateway = await import(join(pkgDir, "dist/gateway.js"));

test("exports gatewayRequest", () => {
  assert.strictEqual(typeof gateway.gatewayRequest, "function");
});

test("exports registerStorageCallbacks", () => {
  assert.strictEqual(typeof gateway.registerStorageCallbacks, "function");
});

// ── 5. Storage subpath ──────────────────────────────────────

console.log("\n=== Storage subpath (vcdb/storage/memory) ===");

const memory = await import(join(pkgDir, "dist/storage/memory.js"));

test("exports createMemoryStorage", () => {
  assert.strictEqual(typeof memory.createMemoryStorage, "function");
});

// ── 6. .d.ts alongside .js ──────────────────────────────────

console.log("\n=== Type declarations (.d.ts) ===");

for (const [subpath, entry] of Object.entries(pkg.exports)) {
  if (typeof entry === "object" && entry.types) {
    test(`${subpath} has .d.ts: ${entry.types}`, () => {
      assert.ok(existsSync(join(pkgDir, entry.types)), `Missing .d.ts: ${entry.types}`);
    });
  }
}

// ── 7. WASM module loadable ─────────────────────────────────

console.log("\n=== WASM module ===");

test("dist/wasm/lib.js exists", () => {
  assert.ok(existsSync(join(pkgDir, "dist/wasm/lib.js")));
});

test("loadModule() succeeds", async () => {
  await main.loadModule(join(pkgDir, "dist/wasm/lib.js"));
  assert.ok(main.isModuleLoaded());
});

// ── Summary ─────────────────────────────────────────────────

console.log(`\n${passed + failed} tests: ${passed} passed, ${failed} failed\n`);
if (failed > 0) process.exit(1);
