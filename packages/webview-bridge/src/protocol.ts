/**
 * Wire protocol for ferrying DataSource calls across a postMessage boundary
 * (VS Code extension ↔ webview, iframe ↔ parent, worker ↔ main thread, ...).
 *
 * Hosts that already exchange other messages on the same channel can coexist
 * with this protocol — the discriminated `type` keys (`ds/request`,
 * `ds/response`) are namespaced.
 */

import type { DataSource } from "@vcdb/data-source";

export type DataSourceMethod = keyof DataSource;

export type DataSourceRequest = {
  readonly type: "ds/request";
  readonly requestId: string;
  readonly method: DataSourceMethod;
  readonly args: readonly unknown[];
};

export type DataSourceResponse =
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

/**
 * Transport-agnostic message channel. Implementations adapt this to the
 * underlying mechanism (vscode webview, window.postMessage, MessageChannel
 * port, ...).
 */
export type Transport = {
  postMessage(message: unknown): void;
  /** Returns an unsubscribe function. */
  onMessage(handler: (message: unknown) => void): () => void;
};

export function isDataSourceRequest(value: unknown): value is DataSourceRequest {
  return (
    typeof value === "object" &&
    value !== null &&
    (value as { type?: unknown }).type === "ds/request"
  );
}

export function isDataSourceResponse(value: unknown): value is DataSourceResponse {
  return (
    typeof value === "object" &&
    value !== null &&
    (value as { type?: unknown }).type === "ds/response"
  );
}
