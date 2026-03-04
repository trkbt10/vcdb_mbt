/**
 * @file WASM VectorDB exports
 */
export {
  loadWasm,
  isLoaded,
  VectorDB,
  gatewayRequest,
  gatewayStorageList,
  gatewayStorageRead,
  gatewayStorageWrite,
  gatewayStorageExists,
} from "./vcdb.js";
export type { Metric, Strategy, SearchResult, GatewayResponse } from "./vcdb.js";
