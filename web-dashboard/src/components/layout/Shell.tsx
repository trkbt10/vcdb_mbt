import React, { useState, useMemo, useCallback } from "react";
import {
  GridLayout,
  type PanelLayoutConfig,
  type LayerDefinition,
} from "react-panel-layout";
import { Sidebar } from "./Sidebar";
import { Header } from "./Header";
import { useDatabase } from "@/contexts/DatabaseContext";
import { ToastContainer, useToast } from "@vcdb/ui-kit/toast";
import type { DatabaseInfo } from "@/features/registry/components";
import { ExplorerPage } from "@/features/explorer";
import styles from "./Shell.module.css";

type ContentPanelProps = {
  selectedDb: DatabaseInfo | null;
};

function ContentPanelInner({ selectedDb }: ContentPanelProps): React.ReactNode {
  if (selectedDb) {
    return <ExplorerPage />;
  }
  return (
    <div className={styles.welcome}>
      <div className={styles.welcomeContent}>
        <div className={styles.welcomeText}>
          <h1>vcdb Dashboard</h1>
          <p>Select or create a collection from the sidebar to start querying the gateway.</p>
        </div>
      </div>
    </div>
  );
}

export function Shell() {
  const { selectDatabase } = useDatabase();
  const { showToast } = useToast();
  const [selectedDb, setSelectedDb] = useState<DatabaseInfo | null>(null);

  const handleSelectDb = useCallback(
    (db: DatabaseInfo) => {
      selectDatabase(db.name);
      setSelectedDb(db);
      showToast(`Connected to ${db.name}`, "success");
    },
    [selectDatabase, showToast],
  );

  const gridConfig = useMemo<PanelLayoutConfig>(
    () => ({
      areas: [["sidebar", "content"]],
      rows: [{ size: "1fr" }],
      columns: [
        { size: "220px", resizable: true, minSize: 180, maxSize: 360 },
        { size: "1fr" },
      ],
    }),
    [],
  );

  const sidebarPanel = (
    <div className={styles.sidebarWrapper}>
      <Sidebar selectedId={selectedDb?.id ?? null} onSelect={handleSelectDb} />
    </div>
  );

  const contentPanel = (
    <div className={styles.contentWrapper}>
      <ContentPanelInner selectedDb={selectedDb} />
    </div>
  );

  const gridLayers = useMemo<LayerDefinition[]>(
    () => [
      { id: "sidebar", gridArea: "sidebar", component: sidebarPanel },
      { id: "content", gridArea: "content", component: contentPanel, scrollable: true },
    ],
    [sidebarPanel, contentPanel],
  );

  return (
    <div className={styles.shell}>
      <Header selectedDb={selectedDb} />
      <div className={styles.main}>
        <GridLayout config={gridConfig} layers={gridLayers} />
      </div>
      <ToastContainer />
    </div>
  );
}
