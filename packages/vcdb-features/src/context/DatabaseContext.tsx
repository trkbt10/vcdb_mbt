import {
  createContext,
  useContext,
  useMemo,
  useState,
  useCallback,
  type ReactNode,
} from "react";
import type { DataSource } from "@vcdb/data-source";
import { createVcdbDataSource } from "@vcdb/data-source-vcdb";
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
import type {
  CreateIndexInput,
  IndexConfig,
  IndexEntry,
} from "vcdb/meta/index-types";
import type { RawAppConfig } from "vcdb/config/types-public";

export type { CreateIndexInput, IndexConfig, IndexEntry, RawAppConfig };

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
  // Index-management surface. The underlying DataSource does not implement
  // these today; they throw at runtime with a clear message. Wire them when
  // the gateway grows index management endpoints.
  listIndexes: () => Promise<IndexEntry[]>;
  createIndex: (input: CreateIndexInput) => Promise<void>;
  dropIndex: (name: string, cascade?: boolean) => Promise<void>;
  rebuildIndex: (name: string) => Promise<void>;
  /** Persist current in-memory state to the configured storage adapter. */
  save: () => Promise<{ ok: boolean }>;
  /** Fetch the current collection's raw app/storage configuration. */
  getDbConfig: () => Promise<RawAppConfig>;
};

const DatabaseContext = createContext<DatabaseContextValue | null>(null);

export type DatabaseProviderProps = {
  children: ReactNode;
  /**
   * Pre-built DataSource to back every operation. Hosts (VS Code webview,
   * tests, alternative backends) pass their own; omit to get the default
   * HTTP gateway client wired through @vcdb/data-source-vcdb.
   */
  dataSource?: DataSource;
  /** Forwarded to createVcdbDataSource when `dataSource` is not provided. */
  apiBase?: string;
};

function notImplemented(name: string): never {
  throw new Error(
    `[vcdb-features] ${name} is not implemented yet — the gateway/DataSource ` +
      `surface does not expose this operation. Track the index-management ` +
      `roadmap before wiring this up in your UI.`,
  );
}

export function DatabaseProvider({
  children,
  dataSource,
  apiBase,
}: DatabaseProviderProps) {
  const resolvedSource = useMemo(
    () => dataSource ?? createVcdbDataSource({ apiBase }),
    [dataSource, apiBase],
  );
  const [databaseName, setDatabaseName] = useState<string | null>(null);
  const api = useCollectionApi(databaseName, resolvedSource);

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
        listIndexes: () => notImplemented("listIndexes"),
        createIndex: () => notImplemented("createIndex"),
        dropIndex: () => notImplemented("dropIndex"),
        rebuildIndex: () => notImplemented("rebuildIndex"),
        save: () => notImplemented("save"),
        getDbConfig: () => notImplemented("getDbConfig"),
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
