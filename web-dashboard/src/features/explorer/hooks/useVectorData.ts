/**
 * @file Hook for fetching and managing vector data
 */
import { useState, useEffect, useCallback } from "react";

export type VectorRow = {
  id: number;
  score?: number;
  attrs: Record<string, unknown> | null;
};

export type ListVectorsResult = {
  rows: Array<{ id: number; attrs: Record<string, unknown> | null }>;
  total: number;
  offset: number;
  limit: number;
};

export type UseVectorDataOptions = {
  /** Function to list vectors from the database */
  listVectors: (options?: { limit?: number; offset?: number }) => Promise<ListVectorsResult>;
  /** Whether the database is connected */
  isConnected: boolean;
  /** Name of the current database (used as dependency for reset) */
  databaseName: string | null;
  /** Initial page size */
  pageSize?: number;
};

export type UseVectorDataResult = {
  /** Vector data rows */
  rows: VectorRow[];
  /** Whether data is being loaded */
  loading: boolean;
  /** Error message if any */
  error: string | null;
  /** Total count of vectors in database */
  total: number;
  /** Reload the data */
  reload: () => Promise<void>;
  /** Set rows (for search results etc) */
  setRows: (rows: VectorRow[]) => void;
};

/**
 * Hook for fetching and managing vector data from the database.
 *
 * Automatically loads initial data when connected and provides
 * reload functionality.
 */
export function useVectorData({
  listVectors,
  isConnected,
  databaseName,
  pageSize = 100,
}: UseVectorDataOptions): UseVectorDataResult {
  const [rows, setRows] = useState<VectorRow[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [total, setTotal] = useState(0);
  const [hasLoadedInitial, setHasLoadedInitial] = useState(false);

  const loadData = useCallback(async () => {
    if (!isConnected || !databaseName) {
      return;
    }

    setLoading(true);
    setError(null);
    try {
      const result = await listVectors({ limit: pageSize });
      setRows(
        result.rows.map((r) => ({
          id: r.id,
          attrs: r.attrs,
        })),
      );
      setTotal(result.total);
    } catch (e) {
      const message = e instanceof Error ? e.message : "Failed to load data";
      setError(message);
      console.error("useVectorData: Failed to load data:", e);
    } finally {
      setLoading(false);
    }
  }, [isConnected, databaseName, listVectors, pageSize]);

  // Load initial data when database is connected
  useEffect(() => {
    if (!isConnected || !databaseName || hasLoadedInitial) {
      return;
    }

    const load = async () => {
      await loadData();
      setHasLoadedInitial(true);
    };
    load();
  }, [isConnected, databaseName, hasLoadedInitial, loadData]);

  // Reset state when database changes
  useEffect(() => {
    setHasLoadedInitial(false);
    setRows([]);
    setTotal(0);
    setError(null);
  }, [databaseName]);

  const reload = useCallback(async () => {
    await loadData();
  }, [loadData]);

  return {
    rows,
    loading,
    error,
    total,
    reload,
    setRows,
  };
}
