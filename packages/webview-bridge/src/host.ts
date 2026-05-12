/**
 * Host-side adapter: takes a real DataSource and a Transport, and replies to
 * incoming `ds/request` messages by invoking the corresponding DataSource
 * method.
 *
 * The host owns the real DataSource (e.g. an HTTP gateway client). The
 * webview-side `createDataSourceClient` reflects calls onto it.
 */

import type { DataSource } from "@vcdb/data-source";
import {
  isDataSourceRequest,
  type DataSourceResponse,
  type Transport,
} from "./protocol.ts";

export type DataSourceHost = {
  /** Stop forwarding requests; idempotent. */
  dispose(): void;
};

export function createDataSourceHost(options: {
  transport: Transport;
  dataSource: DataSource;
}): DataSourceHost {
  const { transport, dataSource } = options;
  let disposed = false;

  const unsubscribe = transport.onMessage(async (message) => {
    if (!isDataSourceRequest(message) || disposed) {
      return;
    }
    const { requestId, method, args } = message;
    let response: DataSourceResponse;
    try {
      const fn = (dataSource as unknown as Record<string, unknown>)[method];
      if (typeof fn !== "function") {
        throw new Error(`DataSource does not implement "${method}"`);
      }
      const result = await (fn as (...a: unknown[]) => unknown).apply(
        dataSource,
        args as unknown[],
      );
      response = { type: "ds/response", requestId, ok: true, result };
    } catch (err) {
      response = {
        type: "ds/response",
        requestId,
        ok: false,
        error: err instanceof Error ? err.message : String(err),
      };
    }
    if (!disposed) {
      transport.postMessage(response);
    }
  });

  return {
    dispose() {
      if (disposed) return;
      disposed = true;
      unsubscribe();
    },
  };
}
