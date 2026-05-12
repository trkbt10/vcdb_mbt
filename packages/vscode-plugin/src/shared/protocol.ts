/**
 * Wire protocol between the VS Code extension host and the webview.
 *
 * The extension owns the real DataSource (HTTP gateway client). The
 * webview consumes a DataSource implementation that ferries calls over
 * postMessage. Concrete DataSource request/response types live in
 * @vcdb/webview-bridge/protocol so they can be reused by other hosts.
 */

export type ExtensionToWebviewMessage =
  | {
      readonly type: "init/config";
      readonly gatewayUrl: string;
    }
  | {
      readonly type: "ds/response";
      readonly requestId: string;
      readonly ok: true;
      readonly result: unknown;
    }
  | {
      readonly type: "ds/response";
      readonly requestId: string;
      readonly ok: false;
      readonly error: string;
    };

export type WebviewToExtensionMessage =
  | {
      readonly type: "webview/ready";
    }
  | {
      readonly type: "webview/log";
      readonly level: "info" | "warn" | "error";
      readonly message: string;
    }
  | {
      readonly type: "ds/request";
      readonly requestId: string;
      readonly method: string;
      readonly args: readonly unknown[];
    };
