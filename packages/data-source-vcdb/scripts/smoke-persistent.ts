/**
 * @file Smoke test for `createPersistentDataSource`.
 *
 * Runs against indexion's `.indexion/cache/agent/orient-vcdb/vcdb` directory
 * (PersistentDB-format files written by indexion's MoonBit FFI calls). It
 * exercises the DataSource end-to-end: discovery, describe, list, search-shape.
 *
 * Run:
 *   bun run packages/data-source-vcdb/scripts/smoke-persistent.ts <dataDir> [dim]
 *
 * Defaults: dataDir = ../indexion/.indexion/cache/agent/orient-vcdb/vcdb
 *           dim     = 256
 */
import { createPersistentDataSource } from "../src/persistent.ts";

const dataDir =
  process.argv[2] ??
  "/Users/terukichi/Workspaces/moonbit/indexion/.indexion/cache/agent/orient-vcdb/vcdb";
const dim = Number(process.argv[3] ?? 256);

const ds = await createPersistentDataSource({
  baseDir: dataDir,
  defaults: { dim, metric: "cosine", strategy: "hnsw", capacity: 4096 },
});

const collections = await ds.listCollections();
console.log("collections:", JSON.stringify(collections, null, 2));

for (const c of collections) {
  const page = await ds.listRecords(c.name, { limit: 3 });
  console.log(`first 3 records of ${c.name} :`);
  for (const r of page.records) {
    console.log(
      "  id =",
      r.id,
      "fields keys =",
      Object.keys(r.fields).filter((k) => k !== "__vector"),
    );
  }
  console.log("  total =", page.total);

  // Exercise the ANN path too — uses HNSW state from the snapshot, so a
  // working result here proves more than just BPTree/CoreStore deserialize.
  const first = await ds.getRecord(c.name, page.records[0].id);
  const probe = first?.fields["__vector"];
  if (Array.isArray(probe)) {
    const hits = await ds.search(c.name, {
      kind: "vector",
      vector: probe as number[],
      k: 3,
    });
    console.log(`  search hits (k=3, probe = first record):`);
    for (const h of hits.records) {
      console.log(
        `    id = ${h.id}  score = ${h.score.toFixed(4)}  path = ${h.fields.path}`,
      );
    }
  }
}
