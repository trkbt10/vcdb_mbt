import assert from "node:assert/strict";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const bridgePath = join(__dirname, "../dist/cloudflare/persistent-do.js");
const { registerPersistentStorage } = await import(bridgePath);

function makeStore(readResult) {
  return {
    async prefetch() {},
    async read() {
      return readResult;
    },
    async write() {},
    async writeAtomic() {},
    async delete() {},
    async exists() {
      return false;
    },
    async list() {
      return [];
    },
  };
}

let registeredRead;
const ffi = {
  persistent_register_wal_storage(_instanceId, read) {
    registeredRead = read;
  },
  persistent_register_snapshot_storage() {},
};

await registerPersistentStorage(
  ffi,
  1,
  makeStore(null),
  makeStore(new Uint8Array([1, 2, 3])),
);

await assert.rejects(
  async () => registeredRead("missing.bin", 0),
  /missing\.bin not found/,
);

console.log("persistent-bridge: missing reads reject");
