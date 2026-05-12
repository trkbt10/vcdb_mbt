import assert from "node:assert/strict";
import { loadModule } from "../dist/ffi/loader.js";
import { VectorDB } from "../dist/vectordb.js";

const calls = [];

const fakeModule = {
  vcdb_create() { return 1; },
  vcdb_create_hnsw() { return 2; },
  vcdb_create_ivf() { return 3; },
  vcdb_destroy() {},
  vcdb_size() { return 0; },
  vcdb_dim() { return 3; },
  vcdb_add(instanceId, idHi, idLo, vector) {
    calls.push(["add", instanceId, idHi, idLo, vector]);
    return 0;
  },
  vcdb_upsert(instanceId, idHi, idLo, vector) {
    calls.push(["upsert", instanceId, idHi, idLo, vector]);
    return 0;
  },
  vcdb_get(_instanceId, idHi, idLo) {
    calls.push(["get", idHi, idLo]);
    return { _0: [1, 2, 3], _1: 1 };
  },
  vcdb_search() {
    return [{ _0: 0, _1: 42, _2: 0.9 }];
  },
  vcdb_has(_instanceId, idHi, idLo) {
    calls.push(["has", idHi, idLo]);
    return 1;
  },
  vcdb_remove(_instanceId, idHi, idLo) {
    calls.push(["remove", idHi, idLo]);
    return 1;
  },
  vcdb_serialize() { return new Uint8Array(0); },
  vcdb_deserialize() { return 4; },
};

await loadModule(fakeModule);

const db = new VectorDB(3);

// VectorId is bigint
const id42 = 42n;
const idBig = 4294967298n; // (1 << 32) + 2 => hi=1, lo=2

db.add(id42, [1, 0, 0]);
db.upsert(idBig, [0, 1, 0]);
assert.deepStrictEqual(db.get(id42), [1, 2, 3]);
assert.strictEqual(db.has(idBig), true);
assert.strictEqual(db.remove(id42), true);

// Search results return bigint IDs
assert.deepStrictEqual(db.search([1, 0, 0], 1), [
  { id: 42n, score: 0.9 },
]);

// Verify hi/lo conversion is correct at the FFI boundary
assert.deepStrictEqual(calls, [
  ["add", 1, 0, 42, [1, 0, 0]],
  ["upsert", 1, 1, 2, [0, 1, 0]],
  ["get", 0, 42],
  ["has", 1, 2],
  ["remove", 0, 42],
]);

console.log("wasm-vcdb: bigint VectorId works correctly");
