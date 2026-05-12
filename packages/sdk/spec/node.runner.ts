#!/usr/bin/env npx tsx
/**
 * @file Node.js storage spec runner
 *
 * Tests: memory, node, cached
 */
import { runStorageSpec } from "./storage.spec.js";
import { createMemoryStorage } from "../src/storage/memory.js";
import { createNodeStorage } from "../src/storage/node.js";
import { CachedStorage } from "../src/storage/cached-storage.js";
import * as fs from "node:fs/promises";
import * as path from "node:path";
import * as os from "node:os";

async function main() {
  console.log("StorageAdapter Spec Runner (Node.js)\n");
  console.log("=====================================");

  let failures = 0;

  // ============================================================================
  // Memory Storage
  // ============================================================================

  try {
    await runStorageSpec({
      name: "MemoryStorage",
      createStorage: async () => createMemoryStorage(),
    });
  } catch {
    failures++;
  }

  // ============================================================================
  // Node Storage
  // ============================================================================

  const tempDir = path.join(os.tmpdir(), `vcdb-spec-${Date.now()}`);

  try {
    await runStorageSpec({
      name: "NodeStorage",
      createStorage: async () => {
        await fs.mkdir(tempDir, { recursive: true });
        return createNodeStorage({ baseDir: tempDir });
      },
      cleanup: async () => {
        await fs.rm(tempDir, { recursive: true, force: true });
      },
    });
  } catch {
    failures++;
  }

  // ============================================================================
  // CachedStorage (with MemoryStorage as backend)
  // ============================================================================

  try {
    let cachedStorage: CachedStorage | null = null;

    await runStorageSpec({
      name: "CachedStorage (memory backend)",
      createStorage: async () => {
        const adapter = createMemoryStorage();
        cachedStorage = new CachedStorage({ adapter });
        const callbacks = cachedStorage.getCallbacks();
        // Return a wrapper that exposes StorageAdapter interface
        return {
          async read(p, k) {
            // Check exists first to distinguish empty file from non-existent
            if (!callbacks.exists(p, k)) return null;
            return callbacks.read(p, k);
          },
          async write(p, d, k) {
            cachedStorage!.getCallbacks().write(p, d, k);
          },
          async delete(p, k) {
            cachedStorage!.getCallbacks().del(p, k);
          },
          async exists(p, k) {
            return cachedStorage!.getCallbacks().exists(p, k);
          },
          async list(k, prefix = "") {
            const all = cachedStorage!.getCallbacks().list(k);
            return prefix ? all.filter((f) => f.startsWith(prefix)) : all;
          },
        };
      },
      cleanup: async () => {
        if (cachedStorage) {
          cachedStorage.clear();
        }
      },
    });
  } catch {
    failures++;
  }

  // ============================================================================
  // CachedStorage flush behavior
  // ============================================================================

  console.log("\n=== CachedStorage Flush Behavior ===\n");

  try {
    const backend = createMemoryStorage();
    const cached = new CachedStorage({ adapter: backend });

    // Write through cache
    cached.getCallbacks().write("flush-test.txt", new Uint8Array([1, 2, 3]), 2);

    // Before flush: backend should be empty
    const beforeFlush = await backend.read("flush-test.txt", 2);
    if (beforeFlush !== null) {
      throw new Error("Backend should be empty before flush");
    }
    console.log("  ✓ write does not immediately persist to backend");

    // hasDirty should be true
    if (!cached.hasDirty()) {
      throw new Error("hasDirty should be true");
    }
    console.log("  ✓ hasDirty returns true after write");

    // Flush
    await cached.flush();

    // After flush: backend should have data
    const afterFlush = await backend.read("flush-test.txt", 2);
    if (afterFlush === null || afterFlush[0] !== 1) {
      throw new Error("Backend should have data after flush");
    }
    console.log("  ✓ flush persists data to backend");

    // hasDirty should be false
    if (cached.hasDirty()) {
      throw new Error("hasDirty should be false after flush");
    }
    console.log("  ✓ hasDirty returns false after flush");

    // Test deletion tracking
    cached.getCallbacks().del("flush-test.txt", 2);
    await cached.flush();
    const afterDelete = await backend.read("flush-test.txt", 2);
    if (afterDelete !== null) {
      throw new Error("Backend should not have deleted file");
    }
    console.log("  ✓ delete is tracked and flushed");

    console.log("\n  All flush behavior tests passed\n");
  } catch (e) {
    console.log(`  ✗ ${e}`);
    failures++;
  }

  // ============================================================================
  // Summary
  // ============================================================================

  console.log("=====================================");
  if (failures > 0) {
    console.log(`\n${failures} spec(s) failed\n`);
    process.exit(1);
  } else {
    console.log("\nAll specs passed!\n");
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
