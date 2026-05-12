import { StrictMode, useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import { ThemeProvider } from "@vcdb/ui-kit/theme";
import { ToastProvider } from "@vcdb/ui-kit/toast";
import { createDataSourceClient } from "@vcdb/webview-bridge";
import type { CollectionDescriptor, DataSource } from "@vcdb/data-source";
import {
  DatabaseProvider,
  ExplorerPage,
  useDatabase,
} from "@vcdb/vcdb-features";
import {
  getVsCodeApi,
  type ExtensionToWebviewMessage,
} from "./vscode-api.ts";
// Global page CSS lives alongside the CSS-modules emitted by every
// component — both ride out under dist/webview.css together.
import "./styles.css";
import { createVscodeWebviewTransport } from "./transport.ts";

function CollectionPicker({
  dataSource,
  onSelect,
}: {
  dataSource: DataSource;
  onSelect: (name: string) => void;
}) {
  const [collections, setCollections] = useState<CollectionDescriptor[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    dataSource
      .listCollections()
      .then((cols) => {
        if (!cancelled) setCollections(cols);
      })
      .catch((err: unknown) => {
        if (!cancelled) setError(err instanceof Error ? err.message : String(err));
      });
    return () => {
      cancelled = true;
    };
  }, [dataSource]);

  if (error) {
    return (
      <p className="vcdb-vscode-error">
        <strong>Error:</strong> {error}
      </p>
    );
  }
  if (collections === null) {
    return <p>Loading collections…</p>;
  }
  if (collections.length === 0) {
    return <p>No collections found. Create one with the vcdb dashboard or CLI.</p>;
  }
  return (
    <ul className="vcdb-vscode-collection-list">
      {collections.map((col) => (
        <li key={col.name}>
          <button
            type="button"
            className="vcdb-vscode-collection-button"
            onClick={() => onSelect(col.name)}
          >
            <span className="vcdb-vscode-collection-name">{col.name}</span>
            <span className="vcdb-vscode-collection-meta">
              {col.recordCount.toLocaleString()} records
            </span>
          </button>
        </li>
      ))}
    </ul>
  );
}

function ConnectedView({ dataSource }: { dataSource: DataSource }) {
  const { databaseName, selectDatabase, disconnect } = useDatabase();

  if (!databaseName) {
    return (
      <main className="vcdb-vscode-main">
        <CollectionPicker dataSource={dataSource} onSelect={selectDatabase} />
      </main>
    );
  }

  return (
    <main className="vcdb-vscode-main vcdb-vscode-explorer">
      <div className="vcdb-vscode-subheader">
        <span>
          <strong>{databaseName}</strong>
        </span>
        <button type="button" onClick={disconnect}>
          Change collection
        </button>
      </div>
      <ExplorerPage />
    </main>
  );
}

function VcdbExplorerWebview() {
  const [gatewayUrl, setGatewayUrl] = useState<string | null>(null);

  const dataSource = useMemo<DataSource>(
    () => createDataSourceClient({ transport: createVscodeWebviewTransport() }),
    [],
  );

  useEffect(() => {
    const api = getVsCodeApi();

    function onMessage(event: MessageEvent<ExtensionToWebviewMessage>) {
      const msg = event.data;
      if (msg.type === "init/config") {
        setGatewayUrl(msg.gatewayUrl);
      }
    }

    window.addEventListener("message", onMessage);
    api.postMessage({ type: "webview/ready" });
    return () => window.removeEventListener("message", onMessage);
  }, []);

  return (
    <div className="vcdb-vscode-shell">
      <header className="vcdb-vscode-header">
        <span>vcdb Explorer</span>
        {gatewayUrl && <code>{gatewayUrl}</code>}
      </header>
      {gatewayUrl === null ? (
        <main className="vcdb-vscode-main">
          <p>Waiting for extension to provide gateway URL…</p>
        </main>
      ) : (
        <DatabaseProvider dataSource={dataSource}>
          <ConnectedView dataSource={dataSource} />
        </DatabaseProvider>
      )}
    </div>
  );
}

const root = document.getElementById("root");
if (root) {
  createRoot(root).render(
    <StrictMode>
      <ThemeProvider>
        <ToastProvider>
          <VcdbExplorerWebview />
        </ToastProvider>
      </ThemeProvider>
    </StrictMode>,
  );
}
