/**
 * @file vcdb Cloudflare Worker — gateway-based deployment.
 *
 * Routes HTTP requests through MoonBit's gateway implementation,
 * using R2 for persistent storage. This is the simplest way to
 * deploy vcdb on Cloudflare Workers.
 *
 * For high-throughput or multi-shard setups, see the
 * cloudflare-do example which uses Durable Objects.
 */
import {
  loadWasm,
  gatewayRequest,
  registerStorageCallbacks,
  type GatewayResponse,
} from "@vcdb/server/wasm";
import { CachedStorage } from "@vcdb/server/storage/wasm-bridge";
import { createR2Storage } from "@vcdb/server/storage/r2";

export interface Env {
  /** R2 bucket for vcdb data persistence. */
  VCDB_DATA: R2Bucket;
}

let cachedStorage: CachedStorage | null = null;

/**
 * Initialize WASM module and storage bridge.
 * Runs once per Worker isolate (not per request).
 */
async function ensureInitialized(env: Env): Promise<void> {
  if (cachedStorage) return;

  // Load vcdb WASM — Wrangler bundles lib.js as a module import.
  await loadWasm();

  // Wire R2 storage through the cache layer for sync WASM callbacks.
  const adapter = createR2Storage({ bucket: env.VCDB_DATA });
  cachedStorage = new CachedStorage({ adapter });
  await cachedStorage.prefetch();

  registerStorageCallbacks(cachedStorage.getCallbacks());
}

/**
 * Map gateway response to HTTP status codes.
 */
function toResponse(result: GatewayResponse): Response {
  if (result.status === "error") {
    const error = result.error ?? "";
    const status = error.includes("not found") || error.includes("Not found")
      ? 404
      : error.includes("already exists") || error.includes("Dimension mismatch") || error.includes("Invalid")
        ? 400
        : 500;
    return Response.json({ error: result.error }, { status });
  }

  if (result.result === true) {
    return Response.json({ status: "ok" });
  }

  return Response.json(result.result);
}

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    // CORS preflight
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    try {
      await ensureInitialized(env);

      const url = new URL(request.url);
      const pathSegments = url.pathname
        .split("/")
        .filter((s) => s.length > 0);

      let body = "";
      if (request.method === "POST" || request.method === "PUT") {
        body = await request.text();
      }

      const result = gatewayRequest(request.method, pathSegments, body);

      // Flush dirty cache entries to R2 after mutations.
      if (cachedStorage?.hasDirty()) {
        await cachedStorage.flush();
      }

      const response = toResponse(result);
      // Append CORS headers
      const headers = new Headers(response.headers);
      for (const [k, v] of Object.entries(CORS_HEADERS)) {
        headers.set(k, v);
      }
      return new Response(response.body, {
        status: response.status,
        headers,
      });
    } catch (e) {
      return Response.json(
        { error: String(e) },
        { status: 500, headers: CORS_HEADERS },
      );
    }
  },
};
