/**
 * @file WASM VectorDB exports
 */
export {
  loadWasm,
  isLoaded,
  VectorDB,
  gatewayRequest,
  registerStorageCallbacks,
  clearStorageCallbacks,
  gatewayStorageList,
  gatewayStorageRead,
  gatewayStorageWrite,
  gatewayStorageExists,
} from "./vcdb.js";
export type { Metric, Strategy, SearchResult, GatewayResponse, WasmStorageCallbacks } from "./vcdb.js";
