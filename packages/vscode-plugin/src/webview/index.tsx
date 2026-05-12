import { StrictMode, useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import { ThemeProvider } from "@vcdb/ui-kit/theme";
import { ToastProvider, ToastContainer } from "@vcdb/ui-kit/toast";
import { createDataSourceClient } from "@vcdb/webview-bridge";
import type { CollectionDescriptor, DataSource } from "@vcdb/data-source";
import {
  getVsCodeApi,
  type ExtensionToWebviewMessage,
} from "./vscode-api.ts";
import { createVscodeWebviewTransport } from "./transport.ts";

function VcdbExplorerWebview() {
  const [gatewayUrl, setGatewayUrl] = useState<string | null>(null);

  const dataSource = useMemo<DataSource>(
    () => createDataSourceClient({ transport: createVscodeWebviewTransport() }),
    [],
  );

  const [collections, setCollections] = useState<CollectionDescriptor[] | null>(null);
  const [error, setError] = useState<string | null>(null);

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

  useEffect(() => {
    if (gatewayUrl === null) {
      return;
    }
    let cancelled = false;
    dataSource
      .listCollections()
      .then((cols) => {
        if (!cancelled) setCollections(cols);
      })
      .catch((err: unknown) => {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : String(err));
        }
      });
    return () => {
      cancelled = true;
    };
  }, [dataSource, gatewayUrl]);

  return (
    <div className="vcdb-vscode-shell">
      <header className="vcdb-vscode-header">
        <span>vcdb Explorer</span>
        {gatewayUrl && <code>{gatewayUrl}</code>}
      </header>
      <main className="vcdb-vscode-main">
        {error && (
          <p className="vcdb-vscode-error">
            <strong>Error:</strong> {error}
          </p>
        )}
        {!error && collections === null && gatewayUrl !== null && (
          <p>Loading collections from {gatewayUrl}…</p>
        )}
        {!error && collections !== null && collections.length === 0 && (
          <p>No collections found. Create one with the vcdb dashboard or CLI.</p>
        )}
        {!error && collections !== null && collections.length > 0 && (
          <ul className="vcdb-vscode-collection-list">
            {collections.map((col) => (
              <li key={col.name}>
                <span className="vcdb-vscode-collection-name">{col.name}</span>
                <span className="vcdb-vscode-collection-meta">
                  {col.recordCount.toLocaleString()} records
                </span>
              </li>
            ))}
          </ul>
        )}
      </main>
      <ToastContainer />
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
