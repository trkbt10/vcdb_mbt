import {
  createContext,
  useContext,
  useState,
  useCallback,
  type ReactNode,
} from "react";
import { useCollectionApi } from "../hooks/useCollectionApi";
import type {
  Attrs,
  BulkResult,
  CollectionStats,
  ListVectorsResult,
  PointRecord,
  SearchHit,
  VectorRowInput,
} from "@vcdb/api-client";

type DatabaseContextValue = {
  databaseName: string | null;
  selectDatabase: (name: string) => void;
  disconnect: () => void;
  isConnected: boolean;
  isLoading: boolean;
  error: Error | null;
  stats: CollectionStats | null;
  refresh: () => void;
  health: () => Promise<{ ok: boolean }>;
  listVectors: (options?: { limit?: number; offset?: number }) => Promise<ListVectorsResult>;
  search: (vector: number[], options?: { k?: number }) => Promise<SearchHit[]>;
  getById: (id: number) => Promise<PointRecord | null>;
  upsert: (id: number, data: { vector: number[]; attrs?: Attrs }) => Promise<void>;
  bulkUpsert: (rows: VectorRowInput[]) => Promise<BulkResult>;
  updateAttrs: (id: number, attrs: Attrs) => Promise<void>;
  deleteById: (id: number) => Promise<void>;
};

const DatabaseContext = createContext<DatabaseContextValue | null>(null);

export function DatabaseProvider({ children }: { children: ReactNode }) {
  const [databaseName, setDatabaseName] = useState<string | null>(null);
  const api = useCollectionApi(databaseName);

  const selectDatabase = useCallback((name: string) => {
    setDatabaseName(name);
  }, []);

  const disconnect = useCallback(() => {
    setDatabaseName(null);
  }, []);

  return (
    <DatabaseContext.Provider
      value={{
        databaseName,
        selectDatabase,
        disconnect,
        isConnected: databaseName !== null,
        isLoading: api.isLoading,
        error: api.error,
        stats: api.stats,
        refresh: api.refresh,
        health: api.health,
        listVectors: api.listVectors,
        search: api.search,
        getById: api.getById,
        upsert: api.upsert,
        bulkUpsert: api.bulkUpsert,
        updateAttrs: api.updateAttrs,
        deleteById: api.deleteById,
      }}
    >
      {children}
    </DatabaseContext.Provider>
  );
}

export function useDatabase(): DatabaseContextValue {
  const context = useContext(DatabaseContext);
  if (!context) {
    throw new Error("useDatabase must be used within DatabaseProvider");
  }
  return context;
}
