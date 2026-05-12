// @vcdb/webview-bridge — typed extension↔webview message protocol plus a
// DataSource implementation that ferries calls over postMessage. Lets a
// webview consume @vcdb/db-viewer as if it were a local DataSource.

export {
  isDataSourceRequest,
  isDataSourceResponse,
  type DataSourceMethod,
  type DataSourceRequest,
  type DataSourceResponse,
  type Transport,
} from "./protocol.ts";
export { createDataSourceHost, type DataSourceHost } from "./host.ts";
export { createDataSourceClient, type DataSourceClient } from "./client.ts";
