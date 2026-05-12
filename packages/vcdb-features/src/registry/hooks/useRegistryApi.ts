import { useState, useCallback, useEffect } from "react";
import { createGatewayClient } from "@vcdb/api-client";
import type { DatabaseInfo } from "../types";

const gatewayClient = createGatewayClient();

export function useRegistryApi() {
  const [databases, setDatabases] = useState<DatabaseInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const collections = await gatewayClient.listCollections();
      setDatabases(
        collections.map((db) => ({
          id: db.name,
          name: db.name,
          stats: {
            size: db.vectors_count,
            dim: db.dim,
            metric: db.metric,
            strategy: db.strategy,
          },
        })),
      );
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to fetch collections");
      setDatabases([]);
    } finally {
      setLoading(false);
    }
  }, []);

  const createDatabase = useCallback(
    async (data: { name: string; config: { dim: number; metric?: string; strategy?: string } }) => {
      await gatewayClient.createCollection(data);
      await refresh();
    },
    [refresh],
  );

  const deleteDatabase = useCallback(
    async (name: string) => {
      await gatewayClient.deleteCollection(name);
      await refresh();
    },
    [refresh],
  );

  useEffect(() => {
    refresh();
  }, [refresh]);

  return {
    databases,
    loading,
    error,
    refresh,
    createDatabase,
    deleteDatabase,
  };
}
