/**
 * Smoke test for MoonBit WASM execution in Node.js
 * Verifies that the WASM module loads and basic operations work.
 */

import assert from "node:assert";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const libPath = join(__dirname, "../dist/wasm/lib.js");

console.log("Loading WASM module...");
const wasm = await import(libPath);
console.log("WASM module loaded successfully");

function idPair(n) {
  return {
    hi: Math.trunc(n / 0x100000000),
    lo: n >>> 0,
  };
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
const id1 = idPair(1);
const addResult = wasm.vcdb_add(instanceId, id1.hi, id1.lo, [1.0, 0.0, 0.0, 0.0]);
assert.strictEqual(addResult, 0, "Add should succeed with code 0");
console.log(`  Added vector id=1`);

// Test: Size after add
console.log("\n[Test] vcdb_size (after add)");
const sizeAfterAdd = wasm.vcdb_size(instanceId);
assert.strictEqual(sizeAfterAdd, 1, "Size should be 1 after add");
console.log(`  Size: ${sizeAfterAdd}`);

// Test: has
console.log("\n[Test] vcdb_has");
const hasVector = wasm.vcdb_has(instanceId, id1.hi, id1.lo);
assert.strictEqual(hasVector, 1, "Should have vector id=1");
const id999 = idPair(999);
const hasNonExistent = wasm.vcdb_has(instanceId, id999.hi, id999.lo);
assert.strictEqual(hasNonExistent, 0, "Should not have vector id=999");
console.log(`  has(1): ${hasVector}, has(999): ${hasNonExistent}`);

// Test: Get vector
console.log("\n[Test] vcdb_get");
const getResult = wasm.vcdb_get(instanceId, id1.hi, id1.lo);
const vector = getResult._0;
const found = getResult._1;
assert.strictEqual(found, 1, "Vector should be found");
assert.strictEqual(vector.length, 4, "Vector should have 4 dimensions");
assert.strictEqual(vector[0], 1.0, "First component should be 1.0");
console.log(`  Vector: [${vector.join(", ")}]`);

// Test: Add more vectors for search
console.log("\n[Test] Adding more vectors for search");
const id2 = idPair(2);
const id3 = idPair(3);
const id4 = idPair(4);
wasm.vcdb_add(instanceId, id2.hi, id2.lo, [0.0, 1.0, 0.0, 0.0]);
wasm.vcdb_add(instanceId, id3.hi, id3.lo, [0.0, 0.0, 1.0, 0.0]);
wasm.vcdb_add(instanceId, id4.hi, id4.lo, [0.5, 0.5, 0.0, 0.0]);
console.log(`  Added vectors 2, 3, 4`);

// Test: Search
console.log("\n[Test] vcdb_search");
const query = [1.0, 0.0, 0.0, 0.0];
const results = wasm.vcdb_search(instanceId, query, 2);
assert.strictEqual(results.length, 2, "Should return 2 results");
// Results should be sorted by similarity - vector 1 (exact match) should be first
assert.strictEqual(results[0]._0, 0, "First result hi should be 0");
assert.strictEqual(results[0]._1, 1, "First result lo should be vector 1");
console.log(`  Results: ${results.map((r) => `id=${r._1}, score=${r._2.toFixed(4)}`).join("; ")}`);

// Test: Upsert (update existing)
console.log("\n[Test] vcdb_upsert");
const upsertResult = wasm.vcdb_upsert(instanceId, id1.hi, id1.lo, [0.0, 0.0, 0.0, 1.0]);
assert.strictEqual(upsertResult, 0, "Upsert should succeed");
const upsertGetResult = wasm.vcdb_get(instanceId, id1.hi, id1.lo);
const updatedVector = upsertGetResult._0;
assert.strictEqual(updatedVector[3], 1.0, "Vector should be updated");
console.log(`  Updated vector 1: [${updatedVector.join(", ")}]`);

// Test: Remove
console.log("\n[Test] vcdb_remove");
const removeResult = wasm.vcdb_remove(instanceId, id1.hi, id1.lo);
assert.strictEqual(removeResult, 1, "Remove should return 1 (success)");
const hasRemoved = wasm.vcdb_has(instanceId, id1.hi, id1.lo);
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

// Test: Gateway API - create collection (POST /collections/{name})
console.log("\n[Test] gateway_request (create collection)");
const createResponse = await wasm.gateway_request(
  "POST",
  ["collections", "test"],
  JSON.stringify({ dim: 4 }),
);
console.log(`  Raw response: ${createResponse}`);
const parsed = JSON.parse(createResponse);
assert.strictEqual(parsed.status, "ok", `Gateway create collection should succeed: ${parsed.error || ""}`);
console.log(`  Created collection: ${JSON.stringify(parsed)}`);

// Test: List collections
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
