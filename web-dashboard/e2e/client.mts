import assert from "node:assert/strict";
import { createGatewayClient } from "../src/api/gateway.ts";

const apiBase = process.env.API_BASE ?? "http://127.0.0.1:6333";
const collectionName = process.env.E2E_COLLECTION_NAME ?? "e2e-client";

const client = createGatewayClient(apiBase);

async function main() {
  console.log("[client] health");
  const health = await client.health();
  assert.equal(health.ok, true);

  console.log("[client] create collection");
  await client.createCollection({
    name: collectionName,
    config: { dim: 4, metric: "cosine", strategy: "hnsw" },
  });

  console.log("[client] list collections");
  const collections = await client.listCollections();
  assert.ok(collections.some((item) => item.name === collectionName));

  console.log("[client] get stats");
  const stats0 = await client.getCollectionStats(collectionName);
  assert.equal(stats0.dim, 4);
  assert.equal(stats0.size, 0);

  console.log("[client] upsert point");
  await client.upsertPoint(collectionName, 1, {
    vector: [1, 0, 0, 0],
    attrs: { label: "alpha" },
  });

  console.log("[client] read point");
  const point = await client.getPoint(collectionName, 1);
  assert.ok(point);
  assert.deepEqual(point.vector, [1, 0, 0, 0]);
  assert.equal(point.attrs.label, "alpha");

  console.log("[client] search");
  const hits = await client.search(collectionName, [1, 0, 0, 0], { k: 5 });
  assert.ok(hits.length > 0);
  assert.equal(hits[0]?.id, 1);

  console.log("[client] update attrs");
  await client.updateAttrs(collectionName, 1, { label: "beta", enabled: true });
  const updated = await client.getPoint(collectionName, 1);
  assert.ok(updated);
  assert.equal(updated.attrs.label, "beta");
  assert.equal(updated.attrs.enabled, true);

  console.log("[client] bulk upsert");
  const bulk = await client.bulkUpsert(collectionName, [
    { id: 2, vector: [0, 1, 0, 0], attrs: { label: "gamma" } },
    { id: 3, vector: [0, 0, 1, 0], attrs: { label: "delta" } },
  ]);
  assert.equal(bulk.ok, true);
  assert.equal(bulk.results.length, 2);

  console.log("[client] list vectors");
  const listed = await client.listVectors(collectionName, { limit: 10 });
  assert.equal(listed.rows.length, 3);
  assert.deepEqual(
    listed.rows.map((row) => row.id),
    [1, 2, 3],
  );

  console.log("[client] refresh stats");
  const stats1 = await client.getCollectionStats(collectionName);
  assert.equal(stats1.size, 3);

  console.log("[client] delete point");
  await client.deletePoint(collectionName, 3);
  const deleted = await client.getPoint(collectionName, 3);
  assert.equal(deleted, null);

  console.log("[client] delete collection");
  await client.deleteCollection(collectionName);
  const collectionsAfterDelete = await client.listCollections();
  assert.ok(!collectionsAfterDelete.some((item) => item.name === collectionName));
}

await main();
