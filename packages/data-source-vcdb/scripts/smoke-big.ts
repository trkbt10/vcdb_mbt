/**
 * @file Write a PersistentDB-format dataset shaped like indexion's
 * `orient-files` collection, using the *current* workspace build of vcdb.
 *
 * Use this when you need to exercise `createPersistentDataSource` (or the
 * VSCode plugin's dataDir mode) but can't read an indexion-written cache
 * because indexion was built from an older `core/attr/bptree.mbt`.
 *
 * Output: /tmp/vcdb-persistent-big/data/{orient-files.data.bin, orient-files.vwal}
 *
 * Run: bun run packages/data-source-vcdb/scripts/smoke-big.ts [recordCount=422]
 */
import { loadModule, PersistentDB, storageToCallbacks } from "vcdb";
import { createNodeStorage } from "vcdb/storage/node";
import { StorageKind } from "vcdb/storage/types";
import { rmSync, mkdirSync } from "node:fs";

const dir = "/tmp/vcdb-persistent-big";
const N = Number(process.argv[2] ?? 422);
const DIM = 256;

rmSync(dir, { recursive: true, force: true });
mkdirSync(`${dir}/data`, { recursive: true });

await loadModule();
const adapter = createNodeStorage({ baseDir: dir });
const cb = storageToCallbacks(adapter, StorageKind.Data);

const db = await PersistentDB.create({
  collectionName: "orient-files",
  basePath: "",
  dim: DIM,
  capacity: 1024,
  metric: "cosine",
  strategy: "hnsw",
  walStorage: cb,
  snapshotStorage: cb,
});

const points: { id: bigint; vector: number[]; payload: Record<string, unknown> }[] = [];
for (let i = 0; i < N; i++) {
  const vector = Array.from({ length: DIM }, () => Math.random() * 2 - 1);
  points.push({
    id: BigInt(-9000000000000000000n + BigInt(i * 31)),
    vector,
    payload: {
      path: `src/sample/file-${i.toString().padStart(4, "0")}.ts`,
      role: i % 4 === 0 ? "test" : "tool",
      owner: i % 7 === 0 ? "doc" : "code",
      source_hash: `${i.toString(16).padStart(8, "0")}-${(i * 2).toString(16).padStart(8, "0")}`,
      structural_summary: `Module ${i}: exports ${1 + (i % 5)} functions and ${i % 3} types.`,
      summary_preview: `Sample record #${i} — preview text for the dashboard's list view.`,
      summary_full:
        i % 3 === 0
          ? `Sample record #${i}: longer narrative used by the inspector when the user expands a row.`
          : undefined,
    },
  });
}

await db.upsert(points);
await db.checkpoint();
console.log("wrote", N, "records to", dir, "— size now =", db.size());
console.log(
  `\nPoint VSCode at this directory:\n` +
    `  "vcdb.dataDir": "${dir}",\n` +
    `  "vcdb.persistent.dim": ${DIM},\n` +
    `  "vcdb.persistent.capacity": 1024`,
);
