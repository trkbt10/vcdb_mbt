/**
 * @file Bidirectional converters between the vcdb gateway-flavoured shapes
 * (`Attrs`, `PointRecord`, `SearchHit`, `CollectionInfo`, `VectorRowInput`)
 * and the protocol-neutral DataSource shapes (`DataRecord`, `ScoredRecord`,
 * `CollectionDescriptor`).
 *
 * Both the gateway → DataSource adapter (this package's main export) and
 * any feature code that needs to consume vcdb-flavoured operations on top
 * of a DataSource (e.g. `@vcdb/vcdb-features/hooks/useCollectionApi`) share
 * these helpers as the single source of truth.
 */

import type {
  Attrs,
  CollectionInfo,
  CollectionStats,
  PointRecord,
  SearchHit,
} from "@vcdb/api-client";
import {
  VECTOR_FIELD,
  type CollectionDescriptor,
  type DataRecord,
  type FieldValue,
  type RecordId,
  type ScoredRecord,
} from "@vcdb/data-source";

/** Cast a DataSource RecordId into the numeric ids vcdb's gateway requires. */
export function idToNumber(id: RecordId): number {
  if (typeof id === "number") return id;
  const parsed = Number(id);
  if (!Number.isFinite(parsed)) {
    throw new Error(`vcdb requires numeric record ids; got ${JSON.stringify(id)}`);
  }
  return parsed;
}

/** Compose a DataRecord from a numeric id, vector, and attribute payload. */
export function toDataRecord(id: number, vector: number[], attrs: Attrs): DataRecord {
  const fields = { ...(attrs as Record<string, FieldValue>) };
  fields[VECTOR_FIELD] = vector;
  return { id, fields };
}

/** Pull the primary vector out of a DataRecord's fields, validating shape. */
export function extractVector(record: DataRecord): number[] {
  const value = record.fields[VECTOR_FIELD];
  if (!Array.isArray(value) || !value.every((n) => typeof n === "number")) {
    throw new Error(
      `DataRecord.fields["${VECTOR_FIELD}"] must be a number[] for vcdb`,
    );
  }
  return value as number[];
}

/**
 * Filter a record's fields down to the JSON-scalar subset that vcdb's
 * Attrs accepts. Non-scalar fields (objects, arrays other than the vector)
 * are dropped — the gateway has no place to put them.
 */
export function extractAttrs(record: DataRecord): Attrs {
  return attrsFromFields(record.fields);
}

/** Same as `extractAttrs` but takes the fields object directly. */
export function attrsFromFields(fields: DataRecord["fields"]): Attrs {
  const attrs: Attrs = {};
  for (const [key, value] of Object.entries(fields)) {
    if (key === VECTOR_FIELD) continue;
    if (
      typeof value === "string" ||
      typeof value === "number" ||
      typeof value === "boolean" ||
      value === null
    ) {
      attrs[key] = value;
    }
  }
  return attrs;
}

/** Convert a gateway PointRecord into a DataRecord with `__vector` populated. */
export function pointToRecord(point: PointRecord): DataRecord {
  return {
    id: point.id,
    fields: {
      ...(point.attrs as DataRecord["fields"]),
      [VECTOR_FIELD]: point.vector,
    },
  };
}

/** Inverse of `pointToRecord` — used when a feature wants gateway-shaped data. */
export function recordToPoint(record: DataRecord): PointRecord {
  return {
    id: idToNumber(record.id),
    vector: extractVector(record),
    attrs: attrsFromFields(record.fields),
  };
}

/** Convert a search result record (scored DataRecord) back to a SearchHit. */
export function scoredRecordToHit(record: ScoredRecord): SearchHit {
  const vectorField = record.fields[VECTOR_FIELD];
  const vector =
    Array.isArray(vectorField) && vectorField.every((n) => typeof n === "number")
      ? (vectorField as number[])
      : undefined;
  return {
    id: idToNumber(record.id),
    score: record.score ?? 0,
    attrs: attrsFromFields(record.fields),
    vector,
  };
}

/** Convert a gateway CollectionInfo into a DataSource CollectionDescriptor. */
export function infoToDescriptor(info: CollectionInfo): CollectionDescriptor {
  return {
    name: info.name,
    recordCount: info.vectors_count,
    schema: {
      fields: [{ name: VECTOR_FIELD, kind: "vector", vectorDim: info.dim }],
    },
  };
}

/**
 * Pull the legacy CollectionStats shape out of a CollectionDescriptor. The
 * metric/strategy are not currently carried through the DataSource layer, so
 * defaults are returned — features that need them should read them out of
 * the original CollectionInfo via the api-client directly.
 */
export function descriptorToStats(desc: CollectionDescriptor): CollectionStats {
  const vectorField = desc.schema?.fields.find((f) => f.name === VECTOR_FIELD);
  return {
    size: desc.recordCount,
    dim: vectorField?.vectorDim ?? 0,
    metric: "Cosine",
    strategy: "HNSW",
  };
}
