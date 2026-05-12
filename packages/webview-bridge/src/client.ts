/**
 * Client-side adapter: returns a DataSource whose every method posts a
 * `ds/request` over the transport and resolves when the matching
 * `ds/response` arrives.
 *
 * The webview consumes this and treats it as if it were a local DataSource;
 * the actual work happens on the host side (see ./host.ts).
 */

import type { DataSource } from "@vcdb/data-source";
import {
  isDataSourceResponse,
  type DataSourceMethod,
  type Transport,
} from "./protocol.ts";

type Pending = {
  resolve: (value: unknown) => void;
  reject: (reason: Error) => void;
};

export type DataSourceClient = DataSource & {
  /** Stop accepting new calls; rejects any in-flight requests. */
  dispose(): void;
};

let counter = 0;
function nextRequestId(): string {
  counter = (counter + 1) | 0;
  return `${Date.now().toString(36)}-${counter.toString(36)}`;
}

export function createDataSourceClient(options: { transport: Transport }): DataSourceClient {
  const { transport } = options;
  const pending = new Map<string, Pending>();
  let disposed = false;

  const unsubscribe = transport.onMessage((message) => {
    if (!isDataSourceResponse(message)) {
      return;
    }
    const entry = pending.get(message.requestId);
    if (!entry) {
      return;
    }
    pending.delete(message.requestId);
    if (message.ok) {
      entry.resolve(message.result);
    } else {
      entry.reject(new Error(message.error));
    }
  });

  function call<T>(method: DataSourceMethod, args: readonly unknown[]): Promise<T> {
    if (disposed) {
      return Promise.reject(new Error("DataSource client has been disposed"));
    }
    const requestId = nextRequestId();
    return new Promise<T>((resolve, reject) => {
      pending.set(requestId, {
        resolve: (value) => resolve(value as T),
        reject,
      });
      transport.postMessage({
        type: "ds/request",
        requestId,
        method,
        args,
      });
    });
  }

  const client: DataSourceClient = {
    health: () => call("health", []),
    listCollections: () => call("listCollections", []),
    describeCollection: (name) => call("describeCollection", [name]),
    listRecords: (collection, opts) => call("listRecords", [collection, opts]),
    getRecord: (collection, id) => call("getRecord", [collection, id]),
    search: (collection, query) => call("search", [collection, query]),
    upsertRecord: (collection, record) => call("upsertRecord", [collection, record]),
    upsertRecords: (collection, records) => call("upsertRecords", [collection, records]),
    deleteRecord: (collection, id) => call("deleteRecord", [collection, id]),
    createCollection: (input) => call("createCollection", [input]),
    deleteCollection: (name) => call("deleteCollection", [name]),
    dispose() {
      if (disposed) return;
      disposed = true;
      unsubscribe();
      const err = new Error("DataSource client disposed before response arrived");
      for (const entry of pending.values()) {
        entry.reject(err);
      }
      pending.clear();
    },
  };
  return client;
}
