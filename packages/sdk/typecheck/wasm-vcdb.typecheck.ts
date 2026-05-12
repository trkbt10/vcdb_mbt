import type { VectorDB } from "../src/db.js";
import type { VectorId, SearchResult } from "../src/index.js";

declare const db: VectorDB;
declare const vector: number[];

const bigintId: VectorId = 1n;

db.add(bigintId, vector);
db.upsert(bigintId, vector);
db.get_(bigintId);
db.has(bigintId);
db.remove(bigintId);

const result: SearchResult = db.search(vector, 1)[0]!;
const resultId: VectorId = result.id;
void resultId;

// @ts-expect-error Vector IDs must not be passed as JS numbers.
db.add(1, vector);
// @ts-expect-error Strings must be parsed explicitly before use.
db.add("1", vector);
// @ts-expect-error Old hi/lo objects are no longer valid VectorIds.
const _oldStyle: VectorId = { hi: 0, lo: 1 };
