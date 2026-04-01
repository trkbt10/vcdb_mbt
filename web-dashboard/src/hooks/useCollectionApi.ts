import { useState, useCallback, useEffect } from "react";
import { createGatewayClient } from "@/api/gateway";
import type {
  Attrs,
  BulkResult,
  CollectionStats,
  ListVectorsResult,
  PointRecord,
  SearchHit,
  VectorRowInput,
} from "@/api/types";

const gatewayClient = createGatewayClient();

export function useCollectionApi(databaseName: string | null) {
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
      setStats(await gatewayClient.getCollectionStats(databaseName));
    } catch (err) {
      setError(err instanceof Error ? err : new Error(String(err)));
      setStats(null);
    } finally {
      setIsLoading(false);
    }
  }, [databaseName]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  const requireDatabaseName = useCallback(() => {
    if (!databaseName) {
      throw new Error("No database selected");
    }
    return databaseName;
  }, [databaseName]);

  const upsert = useCallback(
    async (id: number, data: { vector: number[]; attrs?: Attrs }) => {
      await gatewayClient.upsertPoint(requireDatabaseName(), id, data);
      await refresh();
    },
    [refresh, requireDatabaseName],
  );

  const bulkUpsert = useCallback(
    async (rows: VectorRowInput[]): Promise<BulkResult> => {
      const result = await gatewayClient.bulkUpsert(requireDatabaseName(), rows);
      await refresh();
      return result;
    },
    [refresh, requireDatabaseName],
  );

  const updateAttrs = useCallback(
    async (id: number, attrs: Attrs) => {
      await gatewayClient.updateAttrs(requireDatabaseName(), id, attrs);
      await refresh();
    },
    [refresh, requireDatabaseName],
  );

  const deleteById = useCallback(
    async (id: number) => {
      await gatewayClient.deletePoint(requireDatabaseName(), id);
      await refresh();
    },
    [refresh, requireDatabaseName],
  );

  const getById = useCallback(async (id: number): Promise<PointRecord | null> => {
    return gatewayClient.getPoint(requireDatabaseName(), id);
  }, [requireDatabaseName]);

  const search = useCallback(async (vector: number[], options?: { k?: number }): Promise<SearchHit[]> => {
    return gatewayClient.search(requireDatabaseName(), vector, options);
  }, [requireDatabaseName]);

  const listVectors = useCallback(async (options?: { limit?: number; offset?: number }): Promise<ListVectorsResult> => {
    return gatewayClient.listVectors(requireDatabaseName(), options);
  }, [requireDatabaseName]);

  const health = useCallback(async (): Promise<{ ok: boolean }> => gatewayClient.health(), []);

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
