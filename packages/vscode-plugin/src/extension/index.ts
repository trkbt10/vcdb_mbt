import * as vscode from "vscode";
import { createVcdbDataSource } from "@vcdb/data-source-vcdb";
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

export function activate(context: vscode.ExtensionContext): void {
  const output = vscode.window.createOutputChannel("vcdb");

  context.subscriptions.push(
    vscode.commands.registerCommand("vcdb.openExplorer", () => {
      openExplorerPanel(context, output);
    }),
    output,
  );
}

export function deactivate(): void {
  // No-op. The panel disposes its own resources via the dispose listener.
}

function openExplorerPanel(
  context: vscode.ExtensionContext,
  output: vscode.OutputChannel,
): void {
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

  const gatewayUrl = vscode.workspace
    .getConfiguration("vcdb")
    .get<string>("gatewayUrl", "http://127.0.0.1:6333");

  const dataSource: DataSource = createVcdbDataSource({ apiBase: gatewayUrl });

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
  const dsHost = createDataSourceHost({ transport, dataSource });
  panel.onDidDispose(() => dsHost.dispose());

  panel.webview.html = renderHtml(panel.webview, context.extensionUri);

  panel.webview.onDidReceiveMessage((message: WebviewToExtensionMessage | unknown) => {
    if (isDataSourceRequest(message)) {
      // Already handled by the host transport above.
      return;
    }
    const m = message as WebviewToExtensionMessage;
    switch (m.type) {
      case "webview/ready":
        post(panel, { type: "init/config", gatewayUrl });
        break;
      case "webview/log":
        output.appendLine(`[webview ${m.level}] ${m.message}`);
        break;
    }
  });
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
