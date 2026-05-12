import { useState, useCallback, useMemo, useRef } from "react";
import { useAsyncFn } from "react-use";
import {
  GridLayout,
  type PanelLayoutConfig,
  type LayerDefinition,
} from "react-panel-layout";
import { useDatabase } from "@/contexts/DatabaseContext";
import { useToast } from "@vcdb/ui-kit/toast";
import { useKeyboard, SHORTCUTS } from "@/hooks";
import { Spinner, TabBar, Button, type TabItem } from "@vcdb/ui-kit";
import { DataTable, type ScoredRecord } from "@vcdb/db-viewer";
import { VECTOR_FIELD } from "@vcdb/data-source";
import {
  QueryBar,
  type QueryBarRef,
  type SearchQuery,
  StatsTab,
  InspectorPanel,
  AddRowModal,
  CSVImportModal,
  getActiveFilters,
  type FilterCondition,
} from "./components";
import { useVectorData } from "./hooks";
import { DEFAULT_PORT } from "../../constants";
import styles from "./ExplorerPage.module.css";

type DataRow = {
  id: number;
  score?: number;
  attrs: Record<string, unknown> | null;
  vector?: number[];
};

function toScoredRecord(row: DataRow): ScoredRecord {
  const fields = { ...(row.attrs ?? {}) } as ScoredRecord["fields"];
  if (row.vector) {
    fields[VECTOR_FIELD] = row.vector;
  }
  return { id: row.id, score: row.score, fields };
}

const TABS: TabItem[] = [
  { id: "data", label: "Data" },
  { id: "stats", label: "Stats" },
];

export function ExplorerPage() {
  const { isConnected, isLoading, error, search, refresh, listVectors, databaseName } = useDatabase();
  const toast = useToast();
  const queryBarRef = useRef<QueryBarRef>(null);
  const [activeTab, setActiveTab] = useState("data");
  const [selectedRow, setSelectedRow] = useState<DataRow | null>(null);
  const [filters, setFilters] = useState<FilterCondition[]>([]);
  const [showAddModal, setShowAddModal] = useState(false);
  const [showImportModal, setShowImportModal] = useState(false);

  const { rows, loading: dataLoading, setRows, reload: reloadData } = useVectorData({
    listVectors,
    isConnected,
    databaseName,
    pageSize: 100,
  });

  useKeyboard({
    shortcuts: [
      { ...SHORTCUTS.search, action: () => queryBarRef.current?.focus() },
      { ...SHORTCUTS.escape, action: () => setSelectedRow(null) },
      {
        ...SHORTCUTS.refreshStats,
        action: async () => {
          try {
            await refresh();
            toast.success("Collection stats refreshed");
          } catch (e) {
            toast.error(e instanceof Error ? e.message : "Refresh failed");
          }
        },
      },
      { ...SHORTCUTS.refresh, action: () => refresh() },
    ],
  });

  const applyFilters = useCallback(
    (hits: Array<{ id: number; score: number; attrs: unknown; vector?: number[] }>) => {
      const activeFilters = getActiveFilters(filters);
      if (activeFilters.length === 0) {
        return hits;
      }
      return hits.filter((hit) => {
        const attrs = hit.attrs as Record<string, unknown> | null;
        if (!attrs) {
          return false;
        }
        return activeFilters.every((filter) => {
          const attrValue = String(attrs[filter.key] ?? "");
          const filterValue = filter.value;
          switch (filter.operator) {
            case "=":
              return attrValue === filterValue;
            case "!=":
              return attrValue !== filterValue;
            case ">":
              return parseFloat(attrValue) > parseFloat(filterValue);
            case "<":
              return parseFloat(attrValue) < parseFloat(filterValue);
            case ">=":
              return parseFloat(attrValue) >= parseFloat(filterValue);
            case "<=":
              return parseFloat(attrValue) <= parseFloat(filterValue);
            default:
              return true;
          }
        });
      });
    },
    [filters],
  );

  const [searchState, handleSearch] = useAsyncFn(
    async (query: SearchQuery) => {
      try {
        const hits = await search(query.vector, { k: 100 });
        const filtered = applyFilters(hits);
        setRows(
          filtered.map((hit) => ({
            id: hit.id,
            score: hit.score,
            attrs: hit.attrs as Record<string, unknown> | null,
            vector: hit.vector,
          })),
        );
        toast.success(`Found ${filtered.length} hits`);
      } catch (e) {
        toast.error(e instanceof Error ? e.message : "Search failed");
      }
    },
    [applyFilters, search, setRows, toast],
  );

  const handleModalSuccess = useCallback(() => {
    setSelectedRow(null);
    reloadData();
  }, [reloadData]);

  const gridConfig = useMemo<PanelLayoutConfig>(
    () => ({
      areas: [["main", "inspector"]],
      rows: [{ size: "1fr" }],
      columns: [
        { size: "1fr", resizable: true, minSize: 400 },
        { size: "320px", resizable: true, minSize: 240, maxSize: 480 },
      ],
    }),
    [],
  );

  if (isLoading) {
    return (
      <div className={styles.loading}>
        <Spinner size="lg" />
        <span>Connecting to collection...</span>
      </div>
    );
  }

  if (error || !isConnected) {
    return (
      <div className={styles.error}>
        <h2>Connection Error</h2>
        <p>{error?.message ?? "Failed to connect to vcdb gateway"}</p>
        <p className={styles.hint}>Make sure the HTTP gateway is running on port {DEFAULT_PORT}</p>
        <code className={styles.command}>moon run --target native cmd/native-serve -- --port {DEFAULT_PORT}</code>
      </div>
    );
  }

  const mainPanel = (
    <div className={styles.mainPanel}>
      <QueryBar
        ref={queryBarRef}
        onSearch={handleSearch}
        onFilterChange={setFilters}
        filters={filters}
        loading={searchState.loading}
      />
      <div className={styles.tableContainer}>
        <DataTable
          records={rows.map(toScoredRecord)}
          selectedId={selectedRow?.id}
          onSelect={(record) => {
            const found = rows.find((r) => r.id === record.id);
            setSelectedRow(found ?? null);
          }}
          loading={searchState.loading || dataLoading}
        />
      </div>
    </div>
  );

  const inspectorPanel = (
    <InspectorPanel
      row={selectedRow}
      onUpdate={handleModalSuccess}
      onDelete={handleModalSuccess}
    />
  );

  const gridLayers: LayerDefinition[] = [
    { id: "main", gridArea: "main", component: mainPanel },
    { id: "inspector", gridArea: "inspector", component: inspectorPanel },
  ];

  return (
    <div className={styles.page}>
      <div className={styles.header}>
        <TabBar tabs={TABS} activeTab={activeTab} onTabChange={setActiveTab} />
        {activeTab === "data" && (
          <div className={styles.headerActions}>
            <Button size="sm" onClick={() => setShowAddModal(true)}>
              Add Row
            </Button>
            <Button size="sm" variant="secondary" onClick={() => setShowImportModal(true)}>
              Import CSV
            </Button>
          </div>
        )}
      </div>

      {activeTab === "data" && (
        <div className={styles.gridWrapper}>
          <GridLayout config={gridConfig} layers={gridLayers} />
        </div>
      )}

      {activeTab === "stats" && <StatsTab />}

      <AddRowModal
        isOpen={showAddModal}
        onClose={() => setShowAddModal(false)}
        onSuccess={handleModalSuccess}
      />

      <CSVImportModal
        isOpen={showImportModal}
        onClose={() => setShowImportModal(false)}
        onSuccess={handleModalSuccess}
      />
    </div>
  );
}
