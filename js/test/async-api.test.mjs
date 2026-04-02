/**
 * Integration test for async API (caller-specified instance IDs).
 * Verifies multi-instance isolation, stable IDs across re-init, scroll, count.
 */

import assert from "node:assert";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const libPath = join(__dirname, "../dist/wasm/lib.js");
const wasm = await import(libPath);

const mbNone = { $tag: 0 };
const mbSome = (v) => ({ $tag: 1, _0: v });
const ts = { hi: 0, lo: 0 };

// ── Test: caller-specified instance IDs ──

console.log("[Test] caller-specified instance IDs");
wasm.async_init_db(100, 3, 256);
wasm.async_init_db(200, 3, 256);

wasm.async_upsert(100, [{ _0: 1, _1: [1, 0, 0], _2: '{"shard":"A"}' }], ts);
wasm.async_upsert(200, [{ _0: 1, _1: [0, 1, 0], _2: '{"shard":"B"}' }], ts);

assert.strictEqual(wasm.async_db_size(100), 1);
assert.strictEqual(wasm.async_db_size(200), 1);

const getA = wasm.async_get(100, 1, true);
const getB = wasm.async_get(200, 1, true);
assert.ok(getA._2.includes('"A"'), "Instance 100 should have shard A");
assert.ok(getB._2.includes('"B"'), "Instance 200 should have shard B");
console.log("  Instances isolated by caller-specified IDs");

wasm.async_destroy(100);
wasm.async_destroy(200);

// ── Test: re-init with same ID replaces DB ──

console.log("\n[Test] re-init with same ID replaces DB (simulates DO restart)");
wasm.async_init_db(42, 3, 256);
wasm.async_upsert(42, [{ _0: 1, _1: [1, 0, 0], _2: '{"v":"first"}' }], ts);
assert.strictEqual(wasm.async_db_size(42), 1);

// Simulate DO restart: re-init with same ID
wasm.async_init_db(42, 3, 256);
assert.strictEqual(wasm.async_db_size(42), 0, "Re-init should create fresh DB");
wasm.async_destroy(42);

// ── Test: WAL replay with stable ID ──

console.log("\n[Test] WAL replay preserves data across re-init");
wasm.async_init_db(50, 3, 256);
const walSeg = wasm.async_upsert(50, [
  { _0: 10, _1: [1, 0, 0], _2: '{"v":"persisted"}' },
], ts);
const walHeader = wasm.async_wal_header();
const mergedWal = wasm.async_merge_wal(walHeader, walSeg);
wasm.async_destroy(50);

// Simulate DO restart with WAL replay — same instance ID
const applied = wasm.async_replay_wal_and_init(50, mergedWal, new Uint8Array(0), 3, 256);
assert.strictEqual(applied, 1, "Should apply 1 record");
assert.strictEqual(wasm.async_db_size(50), 1);
const get = wasm.async_get(50, 10, true);
assert.ok(get._0, "Should find replayed record");
assert.ok(get._2.includes("persisted"));
console.log("  Data survived re-init via WAL replay");
wasm.async_destroy(50);

// ── Test: count_filtered ──

console.log("\n[Test] count_filtered");
wasm.async_init_db(60, 3, 256);
wasm.async_upsert(60, [
  { _0: 1, _1: [1, 0, 0], _2: '{"category":"科学"}' },
  { _0: 2, _1: [0, 1, 0], _2: '{"category":"歴史"}' },
  { _0: 3, _1: [0, 0, 1], _2: '{"category":"科学"}' },
], ts);

assert.strictEqual(wasm.async_count_filtered(60, ""), 3);
assert.strictEqual(wasm.async_count_filtered(60, JSON.stringify({ category: "科学" })), 2);
wasm.async_destroy(60);

// ── Test: scroll_filtered ──

console.log("\n[Test] scroll_filtered");
wasm.async_init_db(70, 3, 256);
wasm.async_upsert(70, [
  { _0: 1, _1: [1, 0, 0], _2: '{"category":"科学"}' },
  { _0: 2, _1: [0, 1, 0], _2: '{"category":"歴史"}' },
  { _0: 3, _1: [0, 0, 1], _2: '{"category":"科学"}' },
], ts);

const all = wasm.async_scroll_filtered(70, JSON.stringify({ category: "科学" }), mbNone, 10, true);
assert.strictEqual(all.length, 2);

const page1 = wasm.async_scroll_filtered(70, JSON.stringify({ category: "科学" }), mbNone, 1, true);
const cursor = page1[0]._0;
const page2 = wasm.async_scroll_filtered(70, JSON.stringify({ category: "科学" }), mbSome(cursor), 1, true);
assert.strictEqual(page2.length, 1);
assert.ok(page2[0]._0 > cursor);
wasm.async_destroy(70);

// ── Test: large IDs (> 0x7FFFFFFF) survive WAL round-trip ──

console.log("\n[Test] large ID WAL round-trip");
const largeId = 4241965643; // > 0x7FFFFFFF (the original bug trigger)
wasm.async_init_db(80, 3, 256);
const largeSeg = wasm.async_upsert(80, [{ _0: largeId, _1: [1, 0, 0], _2: '{"big":true}' }], ts);
console.log("  upsert has:", wasm.async_has(80, largeId));
assert.ok(wasm.async_has(80, largeId), "Should have large ID after upsert");

// WAL round-trip
const largeHeader = wasm.async_wal_header();
const largeWal = wasm.async_merge_wal(largeHeader, largeSeg);
wasm.async_destroy(80);
wasm.async_replay_wal_and_init(80, largeWal, new Uint8Array(0), 3, 256);
console.log("  replay has:", wasm.async_has(80, largeId));
assert.ok(wasm.async_has(80, largeId), "Should have large ID after WAL replay");
const largeGet = wasm.async_get(80, largeId, true);
assert.ok(largeGet._0, "Should get large ID");
assert.ok(largeGet._2.includes("big"), "Payload should survive");
console.log("  Large ID WAL round-trip OK");

// Snapshot round-trip
const largeSnap = wasm.async_serialize_snapshot(80);
wasm.async_destroy(80);
wasm.async_init_db_from_snapshot(81, largeSnap);
console.log("  snapshot has:", wasm.async_has(81, largeId));
assert.ok(wasm.async_has(81, largeId), "Should have large ID after snapshot restore");
wasm.async_destroy(81);

// Test several boundary IDs
const boundaryIds = [
  0x7FFFFFFF,     // max signed i32
  0x80000000,     // min unsigned > signed i32
  0xFFFFFFFF,     // max unsigned i32
  4241965643,     // the original problematic ID
  2147483648,     // 2^31
];
console.log("\n[Test] boundary ID round-trips");
for (const bid of boundaryIds) {
  wasm.async_init_db(90, 3, 256);
  const bSeg = wasm.async_upsert(90, [{ _0: bid, _1: [1, 0, 0], _2: '{}' }], ts);
  const bWal = wasm.async_merge_wal(wasm.async_wal_header(), bSeg);
  wasm.async_destroy(90);
  wasm.async_replay_wal_and_init(90, bWal, new Uint8Array(0), 3, 256);
  const bHas = wasm.async_has(90, bid);
  console.log(`  ID ${bid} (0x${bid.toString(16)}): ${bHas ? "OK" : "FAIL"}`);
  assert.ok(bHas, `ID ${bid} should survive WAL round-trip`);
  wasm.async_destroy(90);
}

console.log("\n=== All async API tests passed! ===\n");
