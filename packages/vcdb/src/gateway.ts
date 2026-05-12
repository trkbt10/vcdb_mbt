/**
 * @file Gateway API — HTTP-layer bridge to MoonBit gateway.
 *
 * Depends only on GatewayFfi. Handles request dispatch and
 * synchronous storage callback registration.
 */
import type { SyncStorageCallbacks } from "./ffi/types.js";
import type { StorageKindType } from "./storage/types.js";
import { getGatewayFfi } from "./ffi/loader.js";

export interface GatewayResponse {
  status: "ok" | "error";
  result?: unknown;
  error?: string;
}

export function gatewayRequest(
  method: string,
  path: string[],
  body: unknown = {},
): Promise<GatewayResponse> {
  const ffi = getGatewayFfi();
  const bodyStr = typeof body === "string" ? body : JSON.stringify(body);
  return ffi.gateway_request(method, path, bodyStr)
    .then((value) => JSON.parse(value) as GatewayResponse);
}

export function registerStorageCallbacks(callbacks: SyncStorageCallbacks): void {
  getGatewayFfi().gateway_register_storage(
    callbacks.read,
    callbacks.write,
    callbacks.exists,
    callbacks.del,
    callbacks.list,
  );
}

export function clearStorageCallbacks(): void {
  getGatewayFfi().gateway_clear_storage_callbacks();
}

export function gatewayStorageList(kind: StorageKindType): string[] {
  return getGatewayFfi().gateway_storage_list(kind);
}

export function gatewayStorageRead(path: string, kind: StorageKindType): Uint8Array {
  return getGatewayFfi().gateway_storage_read(path, kind);
}

export function gatewayStorageWrite(path: string, data: Uint8Array, kind: StorageKindType): void {
  getGatewayFfi().gateway_storage_write(path, data, kind);
}

export function gatewayStorageExists(path: string, kind: StorageKindType): boolean {
  return getGatewayFfi().gateway_storage_exists(path, kind);
}
