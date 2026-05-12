import { useState, useMemo, useCallback, type ReactNode } from "react";
import {
  GridLayout,
  type PanelLayoutConfig,
  type LayerDefinition,
} from "react-panel-layout";
import { Sidebar } from "./Sidebar";
import { Header } from "./Header";
import { ToastContainer, useToast } from "@vcdb/ui-kit/toast";
import { useDatabase, type DatabaseInfo } from "@vcdb/vcdb-features";
import styles from "./Shell.module.css";

export type ShellProps = {
  /**
   * Render the main content area. The host decides what page (explorer,
   * wizard, settings, ...) to mount based on the current selection. Default
   * renders a welcome panel when no database is selected; otherwise an
   * unstyled hint to provide your own renderer.
   */
  renderContent?: (selectedDb: DatabaseInfo | null) => ReactNode;
};

function defaultRenderContent(selectedDb: DatabaseInfo | null): ReactNode {
  if (selectedDb) {
    return (
      <div className={styles.welcome}>
        <div className={styles.welcomeContent}>
          <div className={styles.welcomeText}>
            <h1>{selectedDb.name}</h1>
            <p>Connected. Pass a `renderContent` prop to Shell to render a page here.</p>
          </div>
        </div>
      </div>
    );
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

export function Shell({ renderContent = defaultRenderContent }: ShellProps) {
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
    <div className={styles.contentWrapper}>{renderContent(selectedDb)}</div>
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
