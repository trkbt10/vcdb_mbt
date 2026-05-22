import * as path from "node:path";
import * as vscode from "vscode";
import { createVcdbDataSource } from "@vcdb/data-source-vcdb";
import {
  createPersistentDataSource,
  type PersistentDataSourceOptions,
} from "@vcdb/data-source-vcdb/persistent";
import type { DataSource } from "@vcdb/data-source";
import {
  createDataSourceHost,
  isDataSourceRequest,
  type Transport,
} from "@vcdb/webview-bridge";
import type {
  ExtensionToWebviewMessage,
  WebviewToExtensionMessage,
} from "../shared/protocol.ts";

const EXPLORER_VIEW_TYPE = "vcdb.explorerWebview";

type ResolvedSource =
  | { readonly kind: "gateway"; readonly gatewayUrl: string; readonly dataSource: DataSource }
  | {
      readonly kind: "persistent";
      readonly dataDir: string;
      readonly dataSource: DataSource;
    };

export function activate(context: vscode.ExtensionContext): void {
  const output = vscode.window.createOutputChannel("vcdb");

  context.subscriptions.push(
    vscode.commands.registerCommand("vcdb.openExplorer", async () => {
      await openExplorerPanel(context, output);
    }),
    output,
  );
}

export function deactivate(): void {
  // No-op. The panel disposes its own resources via the dispose listener.
}

async function openExplorerPanel(
  context: vscode.ExtensionContext,
  output: vscode.OutputChannel,
): Promise<void> {
  let resolved: ResolvedSource;
  try {
    resolved = await resolveDataSource(output);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    output.appendLine(`[extension error] ${message}`);
    void vscode.window.showErrorMessage(`vcdb: ${message}`);
    return;
  }

  const panel = vscode.window.createWebviewPanel(
    EXPLORER_VIEW_TYPE,
    "vcdb Explorer",
    vscode.ViewColumn.Active,
    {
      enableScripts: true,
      retainContextWhenHidden: true,
      localResourceRoots: [vscode.Uri.joinPath(context.extensionUri, "dist")],
    },
  );

  // The webview-bridge host watches incoming `ds/request` messages on the
  // shared channel. Everything else (init/config, webview/ready, log) flows
  // through the regular onDidReceiveMessage listener below.
  const transport: Transport = {
    postMessage: (message) => {
      void panel.webview.postMessage(message);
    },
    onMessage: (handler) => {
      const sub = panel.webview.onDidReceiveMessage((message) => {
        if (isDataSourceRequest(message)) {
          handler(message);
        }
      });
      return () => sub.dispose();
    },
  };
  const dsHost = createDataSourceHost({ transport, dataSource: resolved.dataSource });
  panel.onDidDispose(() => dsHost.dispose());

  panel.webview.html = renderHtml(panel.webview, context.extensionUri);

  panel.webview.onDidReceiveMessage((message: WebviewToExtensionMessage | unknown) => {
    if (isDataSourceRequest(message)) {
      return;
    }
    const m = message as WebviewToExtensionMessage;
    switch (m.type) {
      case "webview/ready":
        post(panel, {
          type: "init/config",
          gatewayUrl: resolved.kind === "gateway" ? resolved.gatewayUrl : `file://${resolved.dataDir}`,
        });
        break;
      case "webview/log":
        output.appendLine(`[webview ${m.level}] ${m.message}`);
        break;
    }
  });
}

/**
 * Pick the data source backend based on workspace configuration.
 *
 * - `vcdb.dataDir` (preferred when set): in-process PersistentDB over the
 *   directory written by `@vcdb.PersistentDB::init` (e.g. indexion's
 *   `.indexion/cache/agent/orient-vcdb/vcdb`). No HTTP gateway required.
 * - `vcdb.gatewayUrl` (fallback): HTTP gateway (vcdb-server / dashboard).
 */
async function resolveDataSource(output: vscode.OutputChannel): Promise<ResolvedSource> {
  const config = vscode.workspace.getConfiguration("vcdb");
  const dataDir = config.get<string>("dataDir", "").trim();

  if (dataDir) {
    const resolvedDir = resolveWorkspaceRelative(dataDir);
    const persistent = readPersistentOptions(config, resolvedDir);
    output.appendLine(`[extension] persistent mode: ${resolvedDir}`);
    const dataSource = await createPersistentDataSource(persistent);
    return { kind: "persistent", dataDir: resolvedDir, dataSource };
  }

  const gatewayUrl = config.get<string>("gatewayUrl", "http://127.0.0.1:6333");
  output.appendLine(`[extension] gateway mode: ${gatewayUrl}`);
  const dataSource = createVcdbDataSource({ apiBase: gatewayUrl });
  return { kind: "gateway", gatewayUrl, dataSource };
}

function readPersistentOptions(
  config: vscode.WorkspaceConfiguration,
  resolvedDir: string,
): PersistentDataSourceOptions {
  const dim = config.get<number>("persistent.dim", 0);
  if (!dim || dim <= 0) {
    throw new Error(
      `Set "vcdb.persistent.dim" — the vector dimension of the PersistentDB ` +
        `at ${resolvedDir}. Defaults can't be inferred from the binary files.`,
    );
  }
  const capacity = config.get<number>("persistent.capacity", 4096);
  const metric = config.get<string>("persistent.metric", "cosine");
  const strategy = config.get<string>("persistent.strategy", "hnsw");
  return {
    baseDir: resolvedDir,
    defaults: {
      dim,
      capacity,
      metric: metric as PersistentDataSourceOptions["defaults"]["metric"],
      strategy: strategy as PersistentDataSourceOptions["defaults"]["strategy"],
    },
  };
}

function resolveWorkspaceRelative(p: string): string {
  if (path.isAbsolute(p)) return p;
  const folders = vscode.workspace.workspaceFolders ?? [];
  const root = folders[0]?.uri.fsPath;
  if (!root) {
    throw new Error(
      `vcdb.dataDir "${p}" is relative but no workspace folder is open; ` +
        `pass an absolute path.`,
    );
  }
  return path.resolve(root, p);
}

function post(panel: vscode.WebviewPanel, message: ExtensionToWebviewMessage): void {
  void panel.webview.postMessage(message);
}

function renderHtml(
  webview: vscode.Webview,
  extensionUri: vscode.Uri,
): string {
  const scriptUri = webview.asWebviewUri(
    vscode.Uri.joinPath(extensionUri, "dist", "webview.js"),
  );
  const styleUri = webview.asWebviewUri(
    vscode.Uri.joinPath(extensionUri, "dist", "webview.css"),
  );
  const csp = [
    `default-src 'none'`,
    `img-src ${webview.cspSource} data:`,
    `script-src ${webview.cspSource}`,
    `style-src ${webview.cspSource} 'unsafe-inline'`,
    `connect-src https: http: ${webview.cspSource}`,
    `font-src ${webview.cspSource}`,
  ].join("; ");

  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta http-equiv="Content-Security-Policy" content="${csp}" />
    <link rel="stylesheet" href="${styleUri}" />
    <title>vcdb Explorer</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="${scriptUri}"></script>
  </body>
</html>`;
}
