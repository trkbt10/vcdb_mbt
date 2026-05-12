import assert from "node:assert/strict";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const persistentPath = join(__dirname, "../dist/persistent.js");
const { kvStoreToCallbacks } = await import(persistentPath);

function makeStore(readResult) {
  return {
    async read() {
      return readResult;
    },
    async write() {},
    async delete() {},
    async exists() {
      return false;
    },
    async list() {
      return [];
    },
  };
}

// kvStoreToCallbacks wraps a KeyValueStore into AsyncStorageCallbacks.
// When the underlying store returns null, the read callback must reject.
const nullCallbacks = kvStoreToCallbacks(makeStore(null));

await assert.rejects(
  async () => nullCallbacks.read("missing.bin", 0),
  /missing\.bin not found/,
);
console.log("persistent-bridge: missing reads reject");

// When the underlying store returns data, the read callback resolves.
const dataCallbacks = kvStoreToCallbacks(makeStore(new Uint8Array([1, 2, 3])));
const result = await dataCallbacks.read("found.bin", 0);
assert.deepStrictEqual(result, new Uint8Array([1, 2, 3]));
console.log("persistent-bridge: present reads resolve with data");
