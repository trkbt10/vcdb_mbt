/**
 * FFI contract tests — verify that the compiled MoonBit module exposes the
 * correct function signatures and wire format behaviour.
 *
 * These tests are the JS-side mirror of ffi/wbtest.mbt.
 * If the MoonBit FFI changes, both files must be updated together.
 *
 * Wire format SoT: VectorId::to_wire_bytes / VectorId::from_wire_bytes
 *   in core/types/types.mbt
 */

import assert from "node:assert/strict";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const libPath = join(__dirname, "../dist/wasm/lib.js");

console.log("Loading WASM module...");
const wasm = await import(libPath);
console.log("WASM module loaded\n");

let passed = 0;
let failed = 0;

async function test(name, fn) {
  try {
    await fn();
    console.log(`  ✓ ${name}`);
    passed++;
  } catch (e) {
    console.log(`  ✗ ${name}`);
    console.log(`    ${e.message}`);
    failed++;
  }
}

// ── Wire format helpers (mirrors ffi/vector-id.ts) ────────────

function int64ToWireBytes(value) {
  const buf = new Uint8Array(16);
  let v = BigInt.asUintN(64, value);
  for (let i = 7; i >= 0; i--) {
    buf[i] = Number(v & 0xffn);
    v >>= 8n;
  }
  return buf;
}

function wireBytesBigInt(buf) {
  let v = 0n;
  for (let i = 0; i < 8; i++) v = (v << 8n) | BigInt(buf[i]);
  return BigInt.asIntN(64, v);
}

// ── Export surface contract ───────────────────────────────────

console.log("=== Export surface ===");

await test("vcdb_create is exported", () => {
  assert.equal(typeof wasm.vcdb_create, "function");
});
await test("vcdb_create_hnsw is exported", () => {
  assert.equal(typeof wasm.vcdb_create_hnsw, "function");
});
await test("vcdb_create_ivf is exported", () => {
  assert.equal(typeof wasm.vcdb_create_ivf, "function");
});
await test("vcdb_add is exported", () => {
  assert.equal(typeof wasm.vcdb_add, "function");
});
await test("vcdb_upsert is exported", () => {
  assert.equal(typeof wasm.vcdb_upsert, "function");
});
await test("vcdb_get is exported", () => {
  assert.equal(typeof wasm.vcdb_get, "function");
});
await test("vcdb_search is exported", () => {
  assert.equal(typeof wasm.vcdb_search, "function");
});
await test("vcdb_has is exported", () => {
  assert.equal(typeof wasm.vcdb_has, "function");
});
await test("vcdb_remove is exported", () => {
  assert.equal(typeof wasm.vcdb_remove, "function");
});
await test("vcdb_serialize is exported", () => {
  assert.equal(typeof wasm.vcdb_serialize, "function");
});
await test("vcdb_deserialize is exported", () => {
  assert.equal(typeof wasm.vcdb_deserialize, "function");
});
await test("crush_placement_group is exported", () => {
  assert.equal(typeof wasm.crush_placement_group, "function");
});
await test("persistent_init is exported", () => {
  assert.equal(typeof wasm.persistent_init, "function");
});
await test("distributed_merge_search is exported", () => {
  assert.equal(typeof wasm.distributed_merge_search, "function");
});

// Removed in the wire format refactor — these must NOT exist
await test("parse_int64 is removed (old hi/lo era)", () => {
  assert.equal(wasm.parse_int64, undefined);
});
await test("format_int64 is removed (old hi/lo era)", () => {
  assert.equal(wasm.format_int64, undefined);
});

// ── Wire format: vcdb_add accepts Uint8Array(16) ──────────────

console.log("\n=== Wire format ===");

await test("vcdb_add accepts Uint8Array(16) — Int64Id path", () => {
  const inst = wasm.vcdb_create(4);
  const wire = int64ToWireBytes(1n);
  assert.equal(wire.length, 16);
  const r = wasm.vcdb_add(inst, wire, [1.0, 0.0, 0.0, 0.0]);
  assert.equal(r, 0);
  wasm.vcdb_destroy(inst);
});

await test("vcdb_add duplicate returns -2", () => {
  const inst = wasm.vcdb_create(4);
  const wire = int64ToWireBytes(1n);
  wasm.vcdb_add(inst, wire, [1.0, 0.0, 0.0, 0.0]);
  const r = wasm.vcdb_add(inst, wire, [1.0, 0.0, 0.0, 0.0]);
  assert.equal(r, -2);
  wasm.vcdb_destroy(inst);
});

await test("vcdb_add invalid wire bytes returns -1", () => {
  const inst = wasm.vcdb_create(4);
  const bad = new Uint8Array(2); // wrong length
  const r = wasm.vcdb_add(inst, bad, [1.0, 0.0, 0.0, 0.0]);
  assert.equal(r, -1);
  wasm.vcdb_destroy(inst);
});

await test("vcdb_has returns 1/0 with Uint8Array(16)", () => {
  const inst = wasm.vcdb_create(4);
  const wire = int64ToWireBytes(42n);
  wasm.vcdb_add(inst, wire, [1.0, 0.0, 0.0, 0.0]);
  assert.equal(wasm.vcdb_has(inst, wire), 1);
  assert.equal(wasm.vcdb_has(inst, int64ToWireBytes(99n)), 0);
  wasm.vcdb_destroy(inst);
});

await test("vcdb_get returns Tuple2<number[], number> — shape and found flag", () => {
  const inst = wasm.vcdb_create(4);
  const wire = int64ToWireBytes(1n);
  wasm.vcdb_add(inst, wire, [1.0, 2.0, 3.0, 4.0]);
  const r = wasm.vcdb_get(inst, wire);
  // _1: 1 = found, 0 = not found, -1 = error
  assert.equal(r._1, 1, "should be found");
  // _0: vector — length must match dim (vectors may be normalized internally)
  assert.equal(r._0.length, 4, "vector should have 4 dimensions");
  wasm.vcdb_destroy(inst);
});

await test("vcdb_remove returns 1 then 0", () => {
  const inst = wasm.vcdb_create(4);
  const wire = int64ToWireBytes(1n);
  wasm.vcdb_add(inst, wire, [1.0, 0.0, 0.0, 0.0]);
  assert.equal(wasm.vcdb_remove(inst, wire), 1);
  assert.equal(wasm.vcdb_remove(inst, wire), 0);
  wasm.vcdb_destroy(inst);
});

// ── Wire format: vcdb_search returns Uint8Array IDs ───────────

await test("vcdb_search returns Array<Tuple2<Uint8Array, number>>", () => {
  const inst = wasm.vcdb_create(4);
  const id1 = int64ToWireBytes(1n);
  const id2 = int64ToWireBytes(2n);
  wasm.vcdb_add(inst, id1, [1.0, 0.0, 0.0, 0.0]);
  wasm.vcdb_add(inst, id2, [0.0, 1.0, 0.0, 0.0]);

  const results = wasm.vcdb_search(inst, [1.0, 0.0, 0.0, 0.0], 1);
  assert.equal(results.length, 1);

  const hit = results[0];
  assert.ok(hit._0 instanceof Uint8Array, "id should be Uint8Array");
  assert.equal(hit._0.length, 16, "id should be 16 bytes");
  assert.equal(typeof hit._1, "number", "score should be number");

  // Round-trip: decoded ID should match original
  const decodedId = wireBytesBigInt(hit._0);
  assert.equal(decodedId, 1n);

  wasm.vcdb_destroy(inst);
});

// ── Wire format: Int64Id encoding correctness ─────────────────

await test("Int64Id(1) encodes to bytes[7]=1, all other bytes zero", () => {
  const wire = int64ToWireBytes(1n);
  for (let i = 0; i < 16; i++) {
    if (i === 7) assert.equal(wire[i], 1, `byte[7] should be 1`);
    else assert.equal(wire[i], 0, `byte[${i}] should be 0`);
  }
});

await test("Int64Id(-1) encodes to first 8 bytes all 0xFF", () => {
  const wire = int64ToWireBytes(-1n);
  for (let i = 0; i < 8; i++) assert.equal(wire[i], 0xff, `byte[${i}] should be 0xff`);
  for (let i = 8; i < 16; i++) assert.equal(wire[i], 0, `byte[${i}] should be 0`);
});

await test("Int64Id round-trip: encode → add → search → decode", () => {
  const inst = wasm.vcdb_create(4);
  const originalId = 12345678n;
  const wire = int64ToWireBytes(originalId);
  wasm.vcdb_add(inst, wire, [1.0, 0.0, 0.0, 0.0]);

  const results = wasm.vcdb_search(inst, [1.0, 0.0, 0.0, 0.0], 1);
  assert.equal(results.length, 1);
  const decoded = wireBytesBigInt(results[0]._0);
  assert.equal(decoded, originalId);
  wasm.vcdb_destroy(inst);
});

// ── crush_placement_group uses Uint8Array(16) ─────────────────

await test("crush_placement_group accepts Uint8Array(16)", () => {
  const wire = int64ToWireBytes(42n);
  const pg = wasm.crush_placement_group(wire, 16);
  assert.ok(pg >= 0 && pg < 16, `pg ${pg} should be in [0, 16)`);
});

await test("crush_placement_group is deterministic", () => {
  const wire = int64ToWireBytes(42n);
  assert.equal(
    wasm.crush_placement_group(wire, 16),
    wasm.crush_placement_group(wire, 16),
  );
});

await test("crush_placement_group returns -1 for invalid wire bytes", () => {
  const bad = new Uint8Array(2);
  const pg = wasm.crush_placement_group(bad, 16);
  assert.equal(pg, -1);
});

// ── Various ID formats: boundary values ───────────────────────

console.log("\n=== ID boundary values ===");

const ID_CASES = [
  { name: "zero",              value: 0n },
  { name: "one",               value: 1n },
  { name: "max_int64",         value: 9223372036854775807n },
  { name: "min_int64",         value: -9223372036854775808n },
  { name: "negative_one",      value: -1n },
  { name: "2^32",              value: 4294967296n },
  { name: "2^32 - 1",          value: 4294967295n },
  { name: "2^16",              value: 65536n },
  { name: "large_positive",    value: 1234567890123456789n },
  { name: "large_negative",    value: -1234567890123456789n },
  { name: "0x7FFFFFFF",        value: 0x7FFFFFFFn },
  { name: "0x80000000",        value: 0x80000000n },
];

for (const { name, value } of ID_CASES) {
  await test(`ID(${name}): add → has → search → decode round-trip`, () => {
    const inst = wasm.vcdb_create(4);
    const wire = int64ToWireBytes(value);
    assert.equal(wire.length, 16);

    const addResult = wasm.vcdb_add(inst, wire, [1.0, 0.0, 0.0, 0.0]);
    assert.equal(addResult, 0, `add should succeed for ${name}`);

    assert.equal(wasm.vcdb_has(inst, wire), 1, `has should find ${name}`);
    assert.equal(wasm.vcdb_size(inst), 1, `size should be 1`);

    // search returns the ID, decode it and verify round-trip
    const results = wasm.vcdb_search(inst, [1.0, 0.0, 0.0, 0.0], 1);
    assert.equal(results.length, 1);
    const decoded = wireBytesBigInt(results[0]._0);
    assert.equal(decoded, value, `round-trip should preserve ${name}`);

    // get returns found=1
    const getResult = wasm.vcdb_get(inst, wire);
    assert.equal(getResult._1, 1, `get should find ${name}`);

    // remove succeeds
    assert.equal(wasm.vcdb_remove(inst, wire), 1, `remove should succeed for ${name}`);
    assert.equal(wasm.vcdb_has(inst, wire), 0, `has should not find after remove`);

    wasm.vcdb_destroy(inst);
  });
}

// ── Multiple IDs in same DB: no collision ─────────────────────

console.log("\n=== Multiple IDs coexistence ===");

await test("different IDs coexist without collision", () => {
  const inst = wasm.vcdb_create(4);
  const ids = [0n, 1n, -1n, 9223372036854775807n, -9223372036854775808n, 42n, 256n];
  for (let i = 0; i < ids.length; i++) {
    const wire = int64ToWireBytes(ids[i]);
    // Use different vectors so search can distinguish
    const vec = [0.0, 0.0, 0.0, 0.0];
    vec[i % 4] = 1.0;
    const r = wasm.vcdb_add(inst, wire, vec);
    assert.equal(r, 0, `add should succeed for id=${ids[i]}`);
  }
  assert.equal(wasm.vcdb_size(inst), ids.length, "all IDs should be present");

  // Each ID is independently accessible
  for (const id of ids) {
    assert.equal(wasm.vcdb_has(inst, int64ToWireBytes(id)), 1, `should have id=${id}`);
  }

  // Remove one, others unaffected
  wasm.vcdb_remove(inst, int64ToWireBytes(42n));
  assert.equal(wasm.vcdb_size(inst), ids.length - 1);
  assert.equal(wasm.vcdb_has(inst, int64ToWireBytes(42n)), 0);
  assert.equal(wasm.vcdb_has(inst, int64ToWireBytes(0n)), 1);

  wasm.vcdb_destroy(inst);
});

// ── Serialize/deserialize preserves IDs ───────────────────────

console.log("\n=== Serialization preserves IDs ===");

await test("serialize/deserialize preserves various ID values", () => {
  const inst = wasm.vcdb_create(4);
  const ids = [0n, 1n, -1n, 9223372036854775807n, 256n];

  for (const id of ids) {
    wasm.vcdb_add(inst, int64ToWireBytes(id), [1.0, 0.0, 0.0, 0.0]);
  }

  const data = wasm.vcdb_serialize(inst);
  assert.ok(data.length > 0);

  const inst2 = wasm.vcdb_deserialize(data);
  assert.equal(wasm.vcdb_size(inst2), ids.length);

  for (const id of ids) {
    assert.equal(
      wasm.vcdb_has(inst2, int64ToWireBytes(id)), 1,
      `deserialized DB should have id=${id}`,
    );
  }

  wasm.vcdb_destroy(inst);
  wasm.vcdb_destroy(inst2);
});

// ── HNSW and IVF strategies with various IDs ──────────────────

console.log("\n=== Strategy compatibility ===");

for (const [stratName, createFn] of [["hnsw", "vcdb_create_hnsw"], ["ivf", "vcdb_create_ivf"]]) {
  await test(`${stratName}: various IDs add/search round-trip`, () => {
    const inst = wasm[createFn](4);
    const testIds = [1n, 42n, 1000n, 9223372036854775807n];

    for (let i = 0; i < testIds.length; i++) {
      const vec = [0.0, 0.0, 0.0, 0.0];
      vec[i % 4] = 1.0;
      wasm.vcdb_add(inst, int64ToWireBytes(testIds[i]), vec);
    }

    assert.equal(wasm.vcdb_size(inst), testIds.length);

    // Search should return valid wire-format IDs
    const results = wasm.vcdb_search(inst, [1.0, 0.0, 0.0, 0.0], testIds.length);
    for (const r of results) {
      assert.ok(r._0 instanceof Uint8Array, "ID should be Uint8Array");
      assert.equal(r._0.length, 16, "ID should be 16 bytes");
      const decoded = wireBytesBigInt(r._0);
      assert.ok(testIds.includes(decoded), `decoded id=${decoded} should be in test set`);
    }

    wasm.vcdb_destroy(inst);
  });
}

// ── Wire encoding JS ↔ MoonBit parity check ──────────────────

console.log("\n=== JS ↔ MoonBit wire encoding parity ===");

await test("JS bigint encoding matches MoonBit big-endian layout", () => {
  // 0x0102030405060708 → bytes [01, 02, 03, 04, 05, 06, 07, 08, 00*8]
  const wire = int64ToWireBytes(0x0102030405060708n);
  assert.deepEqual(
    Array.from(wire),
    [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
     0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
  );
});

await test("negative values use two's complement big-endian", () => {
  // -2 = 0xFFFFFFFFFFFFFFFE → [FF, FF, FF, FF, FF, FF, FF, FE, 00*8]
  const wire = int64ToWireBytes(-2n);
  assert.equal(wire[0], 0xff);
  assert.equal(wire[6], 0xff);
  assert.equal(wire[7], 0xfe);
  for (let i = 8; i < 16; i++) assert.equal(wire[i], 0);
});

await test("Int64Id(0x80000000): correctly encoded in upper bytes", () => {
  const wire = int64ToWireBytes(0x80000000n);
  // 0x0000000080000000 → [00, 00, 00, 00, 80, 00, 00, 00, 00*8]
  assert.equal(wire[3], 0x00);
  assert.equal(wire[4], 0x80);
  assert.equal(wire[5], 0x00);
});

// ── crush_placement_groups with replicas ─────────────────────

console.log("\n=== CRUSH placement with replicas ===");

await test("crush_placement_groups returns multiple shards when replicas > 1", () => {
  const wire = int64ToWireBytes(42n);
  const shards = wasm.crush_placement_groups(wire, 8, 3);
  assert.equal(shards.length, 3, `expected 3 replicas, got ${shards.length}`);
  // All shard indices should be in [0, 8)
  for (const s of shards) {
    assert.ok(s >= 0 && s < 8, `shard ${s} should be in [0, 8)`);
  }
  // All shard indices should be distinct
  const unique = new Set(shards);
  assert.equal(unique.size, 3, "all replica shards should be distinct");
});

await test("crush_placement_groups is deterministic", () => {
  const wire = int64ToWireBytes(100n);
  const a = wasm.crush_placement_groups(wire, 8, 3);
  const b = wasm.crush_placement_groups(wire, 8, 3);
  assert.deepEqual(a, b);
});

await test("crush_placement_groups with replicas=1 returns single shard", () => {
  const wire = int64ToWireBytes(42n);
  const shards = wasm.crush_placement_groups(wire, 8, 1);
  assert.equal(shards.length, 1);
});

await test("placementGroup consistent with groupUpsert", () => {
  // For each point, the shard from placementGroup should match
  // the shard that groupUpsert assigns it to
  const pgCount = 4;
  for (let i = 0; i < 20; i++) {
    const id = BigInt(i);
    const wire = int64ToWireBytes(id);
    const shard = wasm.crush_placement_group(wire, pgCount);
    const groups = wasm.distributed_group_upsert(
      [{ _0: wire, _1: [1.0, 0.0], _2: "{}" }],
      pgCount,
    );
    assert.equal(groups.length, 1);
    assert.equal(groups[0]._0, shard,
      `ID ${i}: placementGroup=${shard} but groupUpsert assigned to shard ${groups[0]._0}`);
  }
});

// ── Replicated upsert grouping ───────────────────────────────

console.log("\n=== Replicated upsert grouping ===");

await test("distributed_group_upsert_replicated fans out to multiple shards", () => {
  const points = [];
  for (let i = 0; i < 10; i++) {
    points.push({ _0: int64ToWireBytes(BigInt(i)), _1: [1.0, 0.0], _2: "{}" });
  }
  const groups = wasm.distributed_group_upsert_replicated(points, 4, 3);
  // Count total point placements — with 3 replicas, each of the 10 points
  // should appear 3 times across shard groups (total = 30)
  let totalPlacements = 0;
  for (const g of groups) {
    totalPlacements += g._1.length;
  }
  assert.equal(totalPlacements, 30,
    `10 points × 3 replicas = 30 placements, got ${totalPlacements}`);
});

await test("distributed_group_upsert with replicas=1 places each point once", () => {
  const points = [];
  for (let i = 0; i < 10; i++) {
    points.push({ _0: int64ToWireBytes(BigInt(i)), _1: [1.0, 0.0], _2: "{}" });
  }
  const groups = wasm.distributed_group_upsert(points, 4);
  let totalPlacements = 0;
  for (const g of groups) {
    totalPlacements += g._1.length;
  }
  assert.equal(totalPlacements, 10,
    `10 points × 1 replica = 10 placements, got ${totalPlacements}`);
});

// ── Rebalance plan ───────────────────────────────────────────

console.log("\n=== Rebalance plan ===");

await test("distributed_rebalance_plan detects movement on pg_count change", () => {
  const ids = [];
  for (let i = 0; i < 50; i++) {
    ids.push(int64ToWireBytes(BigInt(i)));
  }
  const plan = wasm.distributed_rebalance_plan(ids, 4, 1, 8, 1);
  // Changing pg_count from 4 to 8 should move some vectors
  assert.ok(plan.length > 0,
    `rebalance plan should have actions, got ${plan.length}`);
  // Each action should have add_to or remove_from
  for (const action of plan) {
    const addLen = action._1.length;
    const removeLen = action._2.length;
    assert.ok(addLen > 0 || removeLen > 0,
      "each action should have additions or removals");
  }
});

await test("distributed_rebalance_plan: no change when config identical", () => {
  const ids = [];
  for (let i = 0; i < 20; i++) {
    ids.push(int64ToWireBytes(BigInt(i)));
  }
  const plan = wasm.distributed_rebalance_plan(ids, 4, 1, 4, 1);
  assert.equal(plan.length, 0, "identical config should produce no actions");
});

await test("distributed_rebalance_summary: increasing replicas adds targets", () => {
  const ids = [];
  for (let i = 0; i < 20; i++) {
    ids.push(int64ToWireBytes(BigInt(i)));
  }
  const summary = wasm.distributed_rebalance_summary(ids, 8, 1, 8, 3);
  // Going from 1 to 3 replicas: each of 20 vectors needs 2 additional shards
  assert.equal(summary._0, 20, `all 20 vectors affected, got ${summary._0}`);
  assert.equal(summary._1, 40, `40 additions (20 × 2), got ${summary._1}`);
  assert.equal(summary._2, 0, `0 removals, got ${summary._2}`);
});

// ── Summary ───────────────────────────────────────────────────

console.log(`\n${passed + failed} tests: ${passed} passed, ${failed} failed\n`);
if (failed > 0) process.exit(1);
