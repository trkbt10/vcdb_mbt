/**
 * @file StorageAdapter specification
 *
 * Common spec that all StorageAdapter implementations must pass.
 */
import type { StorageAdapter, StorageKindType } from "../src/storage/types.js";
import { StorageKind } from "../src/storage/types.js";

export interface SpecContext {
  name: string;
  createStorage: () => Promise<StorageAdapter>;
  cleanup?: () => Promise<void>;
}

export async function runStorageSpec(ctx: SpecContext): Promise<void> {
  const { name, createStorage, cleanup } = ctx;

  console.log(`\n=== ${name} ===\n`);

  let passed = 0;
  let failed = 0;

  async function test(description: string, fn: () => Promise<void>) {
    try {
      await fn();
      console.log(`  ✓ ${description}`);
      passed++;
    } catch (e) {
      console.log(`  ✗ ${description}`);
      console.log(`    ${e}`);
      failed++;
    }
  }

  function assert(condition: boolean, message: string) {
    if (!condition) throw new Error(message);
  }

  function assertEq<T>(actual: T, expected: T, message: string) {
    if (actual !== expected) {
      throw new Error(`${message}: expected ${expected}, got ${actual}`);
    }
  }

  function assertArrayEq(actual: Uint8Array | null, expected: Uint8Array | null, message: string) {
    if (actual === null && expected === null) return;
    if (actual === null || expected === null) {
      throw new Error(`${message}: one is null`);
    }
    if (actual.length !== expected.length) {
      throw new Error(`${message}: length mismatch ${actual.length} vs ${expected.length}`);
    }
    for (let i = 0; i < actual.length; i++) {
      if (actual[i] !== expected[i]) {
        throw new Error(`${message}: mismatch at index ${i}`);
      }
    }
  }

  const storage = await createStorage();
  const kinds: StorageKindType[] = [StorageKind.Config, StorageKind.Index, StorageKind.Data];

  // ============================================================================
  // Basic CRUD
  // ============================================================================

  await test("read non-existent file returns null", async () => {
    const result = await storage.read("nonexistent.txt", StorageKind.Data);
    assertEq(result, null, "should return null");
  });

  await test("write and read back", async () => {
    const data = new Uint8Array([1, 2, 3, 4, 5]);
    await storage.write("test.bin", data, StorageKind.Data);
    const result = await storage.read("test.bin", StorageKind.Data);
    assertArrayEq(result, data, "data should match");
  });

  await test("exists returns false for non-existent", async () => {
    const result = await storage.exists("no-such-file.txt", StorageKind.Data);
    assertEq(result, false, "should not exist");
  });

  await test("exists returns true after write", async () => {
    await storage.write("exists-test.txt", new Uint8Array([1]), StorageKind.Data);
    const result = await storage.exists("exists-test.txt", StorageKind.Data);
    assertEq(result, true, "should exist");
  });

  await test("delete removes file", async () => {
    await storage.write("to-delete.txt", new Uint8Array([1]), StorageKind.Data);
    await storage.delete("to-delete.txt", StorageKind.Data);
    const result = await storage.exists("to-delete.txt", StorageKind.Data);
    assertEq(result, false, "should not exist after delete");
  });

  await test("delete non-existent does not throw", async () => {
    await storage.delete("never-existed.txt", StorageKind.Data);
    // Should not throw
  });

  await test("overwrite existing file", async () => {
    const data1 = new Uint8Array([1, 2, 3]);
    const data2 = new Uint8Array([4, 5, 6, 7]);
    await storage.write("overwrite.bin", data1, StorageKind.Data);
    await storage.write("overwrite.bin", data2, StorageKind.Data);
    const result = await storage.read("overwrite.bin", StorageKind.Data);
    assertArrayEq(result, data2, "should have new data");
  });

  // ============================================================================
  // StorageKind isolation
  // ============================================================================

  await test("different kinds are isolated", async () => {
    const configData = new Uint8Array([10]);
    const indexData = new Uint8Array([20]);
    const dataData = new Uint8Array([30]);

    await storage.write("same-name.bin", configData, StorageKind.Config);
    await storage.write("same-name.bin", indexData, StorageKind.Index);
    await storage.write("same-name.bin", dataData, StorageKind.Data);

    const readConfig = await storage.read("same-name.bin", StorageKind.Config);
    const readIndex = await storage.read("same-name.bin", StorageKind.Index);
    const readData = await storage.read("same-name.bin", StorageKind.Data);

    assertArrayEq(readConfig, configData, "config should match");
    assertArrayEq(readIndex, indexData, "index should match");
    assertArrayEq(readData, dataData, "data should match");
  });

  // ============================================================================
  // List
  // ============================================================================

  await test("list returns written files", async () => {
    // Write some files to a specific kind
    await storage.write("list-a.txt", new Uint8Array([1]), StorageKind.Config);
    await storage.write("list-b.txt", new Uint8Array([2]), StorageKind.Config);

    const files = await storage.list(StorageKind.Config);
    assert(files.includes("list-a.txt"), "should include list-a.txt");
    assert(files.includes("list-b.txt"), "should include list-b.txt");
  });

  await test("list with prefix filters results", async () => {
    await storage.write("prefix-foo.txt", new Uint8Array([1]), StorageKind.Index);
    await storage.write("prefix-bar.txt", new Uint8Array([2]), StorageKind.Index);
    await storage.write("other.txt", new Uint8Array([3]), StorageKind.Index);

    const files = await storage.list(StorageKind.Index, "prefix-");
    assert(files.includes("prefix-foo.txt"), "should include prefix-foo.txt");
    assert(files.includes("prefix-bar.txt"), "should include prefix-bar.txt");
    assert(!files.includes("other.txt"), "should not include other.txt");
  });

  await test("list does not include deleted files", async () => {
    await storage.write("to-list-delete.txt", new Uint8Array([1]), StorageKind.Data);
    await storage.delete("to-list-delete.txt", StorageKind.Data);
    const files = await storage.list(StorageKind.Data);
    assert(!files.includes("to-list-delete.txt"), "should not include deleted file");
  });

  // ============================================================================
  // Edge cases
  // ============================================================================

  await test("empty file", async () => {
    const empty = new Uint8Array(0);
    await storage.write("empty.bin", empty, StorageKind.Data);
    const result = await storage.read("empty.bin", StorageKind.Data);
    assertArrayEq(result, empty, "empty file should be readable");
  });

  await test("large file", async () => {
    const large = new Uint8Array(1024 * 100); // 100KB
    for (let i = 0; i < large.length; i++) {
      large[i] = i % 256;
    }
    await storage.write("large.bin", large, StorageKind.Data);
    const result = await storage.read("large.bin", StorageKind.Data);
    assertArrayEq(result, large, "large file should match");
  });

  await test("binary data with all byte values", async () => {
    const allBytes = new Uint8Array(256);
    for (let i = 0; i < 256; i++) {
      allBytes[i] = i;
    }
    await storage.write("all-bytes.bin", allBytes, StorageKind.Data);
    const result = await storage.read("all-bytes.bin", StorageKind.Data);
    assertArrayEq(result, allBytes, "all byte values should be preserved");
  });

  // ============================================================================
  // Cleanup
  // ============================================================================

  if (cleanup) {
    await cleanup();
  }

  console.log(`\n  ${passed} passed, ${failed} failed\n`);

  if (failed > 0) {
    throw new Error(`${name}: ${failed} tests failed`);
  }
}
