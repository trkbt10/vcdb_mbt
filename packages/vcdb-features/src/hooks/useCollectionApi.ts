import { useState, useCallback, useEffect } from "react";
import type {
  Attrs,
  BulkResult,
  CollectionStats,
  ListVectorsResult,
  PointRecord,
  SearchHit,
  VectorRowInput,
} from "@vcdb/api-client";
import { VECTOR_FIELD, type DataSource } from "@vcdb/data-source";
import {
  attrsFromFields,
  descriptorToStats,
  idToNumber,
  recordToPoint,
  scoredRecordToHit,
  toDataRecord,
} from "@vcdb/data-source-vcdb/shape";

/**
 * vcdb-flavored hook over a generic DataSource. Every feature in this package
 * still talks in terms of `Attrs`, `PointRecord`, vectors-and-payloads, but
 * the underlying transport is the protocol-neutral DataSource so the same
 * dashboard can be hosted on different backends (HTTP gateway, in-process
 * SDK, bridged-over-postMessage from a VS Code extension, ...).
 *
 * The DataRecord ↔ vcdb-shape converters live in @vcdb/data-source-vcdb/shape
 * — the single source of truth shared with createVcdbDataSource itself.
 */
export function useCollectionApi(
  databaseName: string | null,
  dataSource: DataSource,
) {
  const [stats, setStats] = useState<CollectionStats | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  const refresh = useCallback(async () => {
    if (!databaseName) {
      setStats(null);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      const desc = await dataSource.describeCollection(databaseName);
      setStats(descriptorToStats(desc));
    } catch (err) {
      setError(err instanceof Error ? err : new Error(String(err)));
      setStats(null);
    } finally {
      setIsLoading(false);
    }
  }, [databaseName, dataSource]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const requireDatabaseName = useCallback(() => {
    if (!databaseName) {
      throw new Error("No database selected");
    }
    return databaseName;
  }, [databaseName]);

  const upsert = useCallback(
    async (id: number, data: { vector: number[]; attrs?: Attrs }) => {
      await dataSource.upsertRecord(
        requireDatabaseName(),
        toDataRecord(id, data.vector, data.attrs ?? {}),
      );
      await refresh();
    },
    [dataSource, refresh, requireDatabaseName],
  );

  const bulkUpsert = useCallback(
    async (rows: VectorRowInput[]): Promise<BulkResult> => {
      const records = rows.map((row) => toDataRecord(row.id, row.vector, row.attrs ?? {}));
      await dataSource.upsertRecords(requireDatabaseName(), records);
      await refresh();
      return {
        ok: true,
        results: rows.map((row) => ({ id: row.id, ok: true })),
      };
    },
    [dataSource, refresh, requireDatabaseName],
  );

  const updateAttrs = useCallback(
    async (id: number, attrs: Attrs) => {
      const existing = await dataSource.getRecord(requireDatabaseName(), id);
      if (!existing) {
        throw new Error(`Point ${id} not found`);
      }
      const point = recordToPoint(existing);
      await dataSource.upsertRecord(
        requireDatabaseName(),
        toDataRecord(id, point.vector, attrs),
      );
      await refresh();
    },
    [dataSource, refresh, requireDatabaseName],
  );

  const deleteById = useCallback(
    async (id: number) => {
      await dataSource.deleteRecord(requireDatabaseName(), id);
      await refresh();
    },
    [dataSource, refresh, requireDatabaseName],
  );

  const getById = useCallback(
    async (id: number): Promise<PointRecord | null> => {
      const record = await dataSource.getRecord(requireDatabaseName(), id);
      return record ? recordToPoint(record) : null;
    },
    [dataSource, requireDatabaseName],
  );

  const search = useCallback(
    async (vector: number[], options?: { k?: number }): Promise<SearchHit[]> => {
      const result = await dataSource.search(requireDatabaseName(), {
        kind: "vector",
        field: VECTOR_FIELD,
        vector,
        k: options?.k,
      });
      return result.records.map(scoredRecordToHit);
    },
    [dataSource, requireDatabaseName],
  );

  const listVectors = useCallback(
    async (options?: { limit?: number; offset?: number }): Promise<ListVectorsResult> => {
      const name = requireDatabaseName();
      const limit = options?.limit ?? 100;
      const offset = options?.offset ?? 0;
      const page = await dataSource.listRecords(name, { limit, offset });
      return {
        rows: page.records.map((record) => ({
          id: idToNumber(record.id),
          attrs: attrsFromFields(record.fields),
        })),
        total: page.total,
        offset,
        limit,
      };
    },
    [dataSource, requireDatabaseName],
  );

  const health = useCallback(async () => dataSource.health(), [dataSource]);

  return {
    stats,
    isLoading,
    error,
    refresh,
    health,
    listVectors,
    search,
    getById,
    upsert,
    bulkUpsert,
    updateAttrs,
    deleteById,
  };
}
