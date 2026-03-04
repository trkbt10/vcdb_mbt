/**
 * vcdb Lambda Handler
 *
 * Responsibilities:
 * - Config: CRUSH settings from env vars
 * - App (this file): routing decisions - which backend for which data
 * - Storage: S3 adapter does I/O
 *
 * For distributed mode, app handles routing using placement config.
 * Library provides: Storage trait, CRUSH functions (placement/crush.mbt)
 */
import type { APIGatewayProxyEventV2, APIGatewayProxyResultV2 } from 'aws-lambda';
import { createS3Storage, type StorageAdapter } from './s3-storage.js';

// ============================================================================
// Config (defines distribution method)
// ============================================================================

const MODE = process.env.VCDB_MODE || 'single';
const BUCKET = process.env.VCDB_S3_BUCKET || 'vcdb-data';
const PREFIX = process.env.VCDB_S3_PREFIX || 'data';

// ============================================================================
// Storage (does persistence)
// ============================================================================

// Storage kind: 0=Config, 1=Index, 2=Data
const StorageKind = { Config: 0, Index: 1, Data: 2 } as const;
type StorageKindType = 0 | 1 | 2;

const kindPrefix = (kind: StorageKindType): string => {
  switch (kind) {
    case StorageKind.Config: return 'config/';
    case StorageKind.Index: return 'index/';
    case StorageKind.Data: return 'data/';
    default: return 'data/';
  }
};

const storage = createS3Storage(BUCKET, PREFIX);
const cache = new Map<string, Uint8Array>();

let wasm: {
  gateway_request: (method: string, path: string[], body: string) => string;
  gateway_register_storage: (
    read: (path: string, kind: StorageKindType) => Uint8Array,
    write: (path: string, data: Uint8Array, kind: StorageKindType) => void,
    exists: (path: string, kind: StorageKindType) => boolean,
    del: (path: string, kind: StorageKindType) => void,
    list: (kind: StorageKindType) => string[]
  ) => void;
} | null = null;

// ============================================================================
// Init
// ============================================================================

async function init(): Promise<void> {
  if (wasm) return;

  // Preload from storage
  const keys = await storage.list();
  await Promise.all(
    keys.map(async (k) => {
      const data = await storage.read(k);
      if (data) cache.set(k, data);
    })
  );

  wasm = await import('./vcdb_gateway.js');

  // Register storage callbacks - use kind prefix for proper isolation
  wasm.gateway_register_storage(
    (path, kind) => cache.get(kindPrefix(kind) + path) || new Uint8Array(0),
    (path, data, kind) => cache.set(kindPrefix(kind) + path, data),
    (path, kind) => cache.has(kindPrefix(kind) + path),
    (path, kind) => cache.delete(kindPrefix(kind) + path),
    (kind) => {
      const prefix = kindPrefix(kind);
      return Array.from(cache.keys())
        .filter(k => k.startsWith(prefix))
        .map(k => k.slice(prefix.length));
    }
  );
}

// ============================================================================
// Persist
// ============================================================================

async function persist(): Promise<void> {
  // Simple: write all cached data to storage
  await Promise.all(
    Array.from(cache.entries()).map(([k, v]) => storage.write(k, v))
  );
}

// ============================================================================
// Handler
// ============================================================================

export const handler = async (
  event: APIGatewayProxyEventV2
): Promise<APIGatewayProxyResultV2> => {
  try {
    await init();

    const method = event.requestContext.http.method;
    if (method === 'OPTIONS') {
      return { statusCode: 204, headers: cors(), body: '' };
    }

    const path = (event.rawPath || '/').split('/').filter((s) => s.length > 0);
    const responseStr = wasm!.gateway_request(method, path, event.body || '');

    // Persist after mutations
    if (['POST', 'PUT', 'DELETE'].includes(method)) {
      await persist();
    }

    const response = JSON.parse(responseStr);
    const statusCode =
      response.status === 'error'
        ? response.error?.toLowerCase().includes('not found') ? 404 : 400
        : 200;

    return {
      statusCode,
      headers: { 'Content-Type': 'application/json', ...cors() },
      body: responseStr,
    };
  } catch (e) {
    return {
      statusCode: 500,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ error: String(e) }),
    };
  }
};

const cors = () => ({
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': '*',
  'Access-Control-Allow-Headers': '*',
});
