/**
 * Integration test for async API (hi/lo ID pairs, no Double IDs).
 * Verifies multi-instance isolation, boundary IDs, scroll, count.
 */

import assert from "node:assert";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const libPath = join(__dirname, "../dist/wasm/lib.js");
const wasm = await import(libPath);

const ts = { hi: 0, lo: 0 };

/** Split a JS number into hi/lo pair (matching vid_from_pair). */
function idPair(n) {
  const lo = n | 0;           // signed i32
  const hi = (n / 0x100000000) | 0;
  return { hi, lo };
}

// ── Test: basic instance with hi/lo IDs ──

console.log("[Test] hi/lo ID basics");
wasm.async_init_db(100, 3, 256);
const p = idPair(42);
wasm.async_upsert(100, [{ _0: p.hi, _1: p.lo, _2: [1, 0, 0], _3: '{"v":1}' }], ts);
assert.strictEqual(wasm.async_db_size(100), 1);
assert.ok(wasm.async_has(100, p.hi, p.lo));
const g = wasm.async_get(100, p.hi, p.lo, true);
assert.ok(g._0);
assert.ok(g._2.includes('"v"'));
wasm.async_destroy(100);

// ── Test: large ID (> 0x7FFFFFFF) round-trips via WAL ──

console.log("\n[Test] large ID WAL round-trip");
const largeId = 4241965643; // > 0x7FFFFFFF — the original bug trigger
const lp = idPair(largeId);
console.log(`  ID ${largeId} → hi=${lp.hi} lo=${lp.lo}`);

wasm.async_init_db(200, 3, 256);
wasm.async_upsert(200, [{ _0: lp.hi, _1: lp.lo, _2: [1, 0, 0], _3: '{"big":true}' }], ts);
assert.ok(wasm.async_has(200, lp.hi, lp.lo), "has after upsert");

// WAL round-trip
const seg = wasm.async_upsert(200, [{ _0: lp.hi, _1: lp.lo, _2: [1, 0, 0], _3: '{"big":true}' }], ts);
const header = wasm.async_wal_header();
const wal = wasm.async_merge_wal(header, seg);
wasm.async_destroy(200);
wasm.async_replay_wal_and_init(200, wal, new Uint8Array(0), 3, 256);
assert.ok(wasm.async_has(200, lp.hi, lp.lo), "has after WAL replay");
console.log("  WAL round-trip OK");

// Snapshot round-trip
const snap = wasm.async_serialize_snapshot(200);
wasm.async_destroy(200);
wasm.async_init_db_from_snapshot(201, snap);
assert.ok(wasm.async_has(201, lp.hi, lp.lo), "has after snapshot restore");
console.log("  Snapshot round-trip OK");
wasm.async_destroy(201);

// ── Test: boundary IDs ──

console.log("\n[Test] boundary ID round-trips");
const boundaryIds = [
  0x7FFFFFFF,     // max signed i32
  0x80000000,     // min unsigned > signed i32
  0xFFFFFFFF,     // max unsigned i32
  4241965643,     // the original problematic ID
  2147483648,     // 2^31
  1,              // minimal
  0,              // zero
];
for (const bid of boundaryIds) {
  const bp = idPair(bid);
  wasm.async_init_db(300, 3, 256);
  const bSeg = wasm.async_upsert(300, [{ _0: bp.hi, _1: bp.lo, _2: [1, 0, 0], _3: '{}' }], ts);
  const bWal = wasm.async_merge_wal(wasm.async_wal_header(), bSeg);
  wasm.async_destroy(300);
  wasm.async_replay_wal_and_init(300, bWal, new Uint8Array(0), 3, 256);
  const has = wasm.async_has(300, bp.hi, bp.lo);
  console.log(`  ID ${bid} (0x${bid.toString(16)}) hi=${bp.hi} lo=${bp.lo}: ${has ? "OK" : "FAIL"}`);
  assert.ok(has, `ID ${bid} should survive WAL round-trip`);
  wasm.async_destroy(300);
}

// ── Test: search returns hi/lo IDs ──

console.log("\n[Test] search returns hi/lo");
wasm.async_init_db(400, 3, 256);
const sp = idPair(42);
wasm.async_upsert(400, [{ _0: sp.hi, _1: sp.lo, _2: [1, 0, 0], _3: '{"v":1}' }], ts);
const results = wasm.async_search(400, [1, 0, 0], 1, true, "");
assert.strictEqual(results.length, 1);
assert.strictEqual(results[0]._0, sp.hi);
assert.strictEqual(results[0]._1, sp.lo);
assert.ok(results[0]._2 > 0.9); // score
assert.ok(results[0]._3.includes('"v"')); // payload
wasm.async_destroy(400);

// ── Test: scroll_filtered returns hi/lo ──

console.log("\n[Test] scroll_filtered with hi/lo");
wasm.async_init_db(500, 3, 256);
wasm.async_upsert(500, [
  { _0: 0, _1: 1, _2: [1, 0, 0], _3: '{"category":"科学"}' },
  { _0: 0, _1: 2, _2: [0, 1, 0], _3: '{"category":"歴史"}' },
  { _0: 0, _1: 3, _2: [0, 0, 1], _3: '{"category":"科学"}' },
], ts);

const scrolled = wasm.async_scroll_filtered(500, JSON.stringify({ category: "科学" }), 0, 0, false, 10, true);
assert.strictEqual(scrolled.length, 2);
// Results have (hi, lo, payload) tuples
assert.strictEqual(scrolled[0]._0, 0); // hi
assert.ok(scrolled[0]._2.includes("科学")); // payload
console.log("  Scroll returns hi/lo pairs");
wasm.async_destroy(500);

// ── Test: count_filtered ──

console.log("\n[Test] count_filtered");
wasm.async_init_db(600, 3, 256);
wasm.async_upsert(600, [
  { _0: 0, _1: 1, _2: [1, 0, 0], _3: '{"category":"科学"}' },
  { _0: 0, _1: 2, _2: [0, 1, 0], _3: '{"category":"歴史"}' },
], ts);
assert.strictEqual(wasm.async_count_filtered(600, ""), 2);
assert.strictEqual(wasm.async_count_filtered(600, JSON.stringify({ category: "科学" })), 1);
wasm.async_destroy(600);

// ── Test: multi-instance isolation ──

console.log("\n[Test] multi-instance isolation");
wasm.async_init_db(700, 3, 256);
wasm.async_init_db(701, 3, 256);
wasm.async_upsert(700, [{ _0: 0, _1: 1, _2: [1, 0, 0], _3: '{"s":"A"}' }], ts);
wasm.async_upsert(701, [{ _0: 0, _1: 1, _2: [0, 1, 0], _3: '{"s":"B"}' }], ts);
assert.ok(wasm.async_get(700, 0, 1, true)._2.includes('"A"'));
assert.ok(wasm.async_get(701, 0, 1, true)._2.includes('"B"'));
wasm.async_destroy(700);
assert.strictEqual(wasm.async_db_size(701), 1);
wasm.async_destroy(701);

console.log("\n=== All async API tests passed! ===\n");
