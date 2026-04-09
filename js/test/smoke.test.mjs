/**
 * Smoke test for MoonBit WASM execution in Node.js.
 * Verifies that the WASM module loads and basic operations work.
 *
 * VectorId wire format: Uint8Array(16)
 *   Int64Id(v) → bytes 0-7 big-endian, bytes 8-15 = 0x00
 */

import assert from "node:assert";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const libPath = join(__dirname, "../dist/wasm/lib.js");

console.log("Loading WASM module...");
const wasm = await import(libPath);
console.log("WASM module loaded successfully");

/** Encode a JS number as an Int64Id wire bytes (Uint8Array(16)). */
function wireId(n) {
  const buf = new Uint8Array(16);
  let v = BigInt.asUintN(64, BigInt(n));
  for (let i = 7; i >= 0; i--) {
    buf[i] = Number(v & 0xffn);
    v >>= 8n;
  }
  return buf;
}

/** Decode the Int64 value from wire bytes (bytes 0-7, big-endian). */
function decodeId(buf) {
  let v = 0n;
  for (let i = 0; i < 8; i++) v = (v << 8n) | BigInt(buf[i]);
  return BigInt.asIntN(64, v);
}

// Test: Create VectorDB instance
console.log("\n[Test] vcdb_create");
const instanceId = wasm.vcdb_create(4);
assert.ok(instanceId > 0, "Instance ID should be positive");
console.log(`  Created instance: ${instanceId}`);

// Test: Get dimension
console.log("\n[Test] vcdb_dim");
const dim = wasm.vcdb_dim(instanceId);
assert.strictEqual(dim, 4, "Dimension should be 4");
console.log(`  Dimension: ${dim}`);

// Test: Initial size should be 0
console.log("\n[Test] vcdb_size (empty)");
const initialSize = wasm.vcdb_size(instanceId);
assert.strictEqual(initialSize, 0, "Initial size should be 0");
console.log(`  Size: ${initialSize}`);

// Test: Add vector
console.log("\n[Test] vcdb_add");
const w1 = wireId(1);
const addResult = wasm.vcdb_add(instanceId, w1, [1.0, 0.0, 0.0, 0.0]);
assert.strictEqual(addResult, 0, "Add should succeed with code 0");
console.log(`  Added vector id=1`);

// Test: Size after add
console.log("\n[Test] vcdb_size (after add)");
const sizeAfterAdd = wasm.vcdb_size(instanceId);
assert.strictEqual(sizeAfterAdd, 1, "Size should be 1 after add");
console.log(`  Size: ${sizeAfterAdd}`);

// Test: has
console.log("\n[Test] vcdb_has");
const hasVector = wasm.vcdb_has(instanceId, w1);
assert.strictEqual(hasVector, 1, "Should have vector id=1");
const hasNonExistent = wasm.vcdb_has(instanceId, wireId(999));
assert.strictEqual(hasNonExistent, 0, "Should not have vector id=999");
console.log(`  has(1): ${hasVector}, has(999): ${hasNonExistent}`);

// Test: Get vector
console.log("\n[Test] vcdb_get");
const getResult = wasm.vcdb_get(instanceId, w1);
const vector = getResult._0;
const found = getResult._1;
assert.strictEqual(found, 1, "Vector should be found");
assert.strictEqual(vector.length, 4, "Vector should have 4 dimensions");
console.log(`  Vector (normalized): [${vector.map(v => v.toFixed(4)).join(", ")}]`);

// Test: Add more vectors for search
console.log("\n[Test] Adding more vectors for search");
const w2 = wireId(2);
const w3 = wireId(3);
const w4 = wireId(4);
wasm.vcdb_add(instanceId, w2, [0.0, 1.0, 0.0, 0.0]);
wasm.vcdb_add(instanceId, w3, [0.0, 0.0, 1.0, 0.0]);
wasm.vcdb_add(instanceId, w4, [0.5, 0.5, 0.0, 0.0]);
console.log(`  Added vectors 2, 3, 4`);

// Test: Search — results are Tuple2<Uint8Array(16), score>
console.log("\n[Test] vcdb_search");
const query = [1.0, 0.0, 0.0, 0.0];
const results = wasm.vcdb_search(instanceId, query, 2);
assert.strictEqual(results.length, 2, "Should return 2 results");
assert.ok(results[0]._0 instanceof Uint8Array, "Result ID should be Uint8Array");
assert.strictEqual(results[0]._0.length, 16, "Result ID should be 16 bytes");
// Top result should be id=1 (exact match)
const topId = decodeId(results[0]._0);
assert.strictEqual(topId, 1n, "Top result should be id=1");
console.log(`  Results: ${results.map((r) => `id=${decodeId(r._0)}, score=${r._1.toFixed(4)}`).join("; ")}`);

// Test: Upsert (update existing)
console.log("\n[Test] vcdb_upsert");
const upsertResult = wasm.vcdb_upsert(instanceId, w1, [0.0, 0.0, 0.0, 1.0]);
assert.strictEqual(upsertResult, 0, "Upsert should succeed");
const upsertGetResult = wasm.vcdb_get(instanceId, w1);
assert.strictEqual(upsertGetResult._1, 1, "Updated vector should be found");
console.log(`  Updated vector 1`);

// Test: Remove
console.log("\n[Test] vcdb_remove");
const removeResult = wasm.vcdb_remove(instanceId, w1);
assert.strictEqual(removeResult, 1, "Remove should return 1 (success)");
const hasRemoved = wasm.vcdb_has(instanceId, w1);
assert.strictEqual(hasRemoved, 0, "Removed vector should not exist");
console.log(`  Removed vector 1`);

// Test: Serialize/Deserialize
console.log("\n[Test] vcdb_serialize / vcdb_deserialize");
const serialized = wasm.vcdb_serialize(instanceId);
assert.ok(serialized.length > 0, "Serialized data should not be empty");
console.log(`  Serialized size: ${serialized.length} bytes`);

const newInstanceId = wasm.vcdb_deserialize(serialized);
assert.ok(newInstanceId > 0, "Deserialized instance ID should be positive");
const deserializedSize = wasm.vcdb_size(newInstanceId);
assert.strictEqual(deserializedSize, 3, "Deserialized DB should have 3 vectors");
console.log(`  Deserialized instance: ${newInstanceId}, size: ${deserializedSize}`);

// Test: HNSW strategy
console.log("\n[Test] vcdb_create_hnsw");
const hnswId = wasm.vcdb_create_hnsw(4);
assert.ok(hnswId > 0, "HNSW instance should be created");
console.log(`  HNSW instance: ${hnswId}`);

// Test: IVF strategy
console.log("\n[Test] vcdb_create_ivf");
const ivfId = wasm.vcdb_create_ivf(4);
assert.ok(ivfId > 0, "IVF instance should be created");
console.log(`  IVF instance: ${ivfId}`);

// Test: Gateway API
console.log("\n[Test] gateway_request (create collection)");
const createResponse = await wasm.gateway_request(
  "POST",
  ["collections", "test"],
  JSON.stringify({ dim: 4 }),
);
const parsed = JSON.parse(createResponse);
assert.strictEqual(parsed.status, "ok", `Gateway create should succeed: ${parsed.error || ""}`);
console.log(`  Created collection: ${JSON.stringify(parsed)}`);

console.log("\n[Test] gateway_request (list collections)");
const listResponse = await wasm.gateway_request("GET", ["collections"], "{}");
const listParsed = JSON.parse(listResponse);
assert.strictEqual(listParsed.status, "ok", "Gateway list should succeed");
console.log(`  Collections: ${JSON.stringify(listParsed)}`);

// Cleanup
console.log("\n[Cleanup]");
wasm.vcdb_destroy(instanceId);
wasm.vcdb_destroy(newInstanceId);
wasm.vcdb_destroy(hnswId);
wasm.vcdb_destroy(ivfId);
console.log("  All instances destroyed");

console.log("\n=== All smoke tests passed! ===\n");
