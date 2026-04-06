/**
 * @file Cloudflare Worker entry point — Durable Objects example.
 *
 * Loads vcdb WASM once per isolate. All routing, merge, and ID
 * parsing is delegated to vcdb core FFI — no local reimplementations.
 */
import { createShardRouter, type ShardRouter } from "./infra/shard-router.ts";
import type { MbInt64, PersistentFFI } from "@vcdb/server/storage/persistent-bridge";
import type { Bindings } from "./types.ts";

export { VcdbStore } from "./infra/vcdb-do.ts";

const SHARD_COUNT = 8;

let ffi: PersistentFFI | null = null;
let router: ShardRouter | null = null;

async function ensureInitialized(): Promise<{
  ffi: PersistentFFI;
  router: ShardRouter;
}> {
  if (ffi && router) return { ffi, router };
  ffi = await import("@vcdb/server/wasm/lib.js");
  router = createShardRouter(SHARD_COUNT, ffi);
  return { ffi, router };
}

/**
 * Parse a string ID via core FFI (SoT for string → MbInt64).
 * Throws on invalid input.
 */
function parseId(vcdb: PersistentFFI, input: string): MbInt64 {
  const result = vcdb.parse_int64(input);
  if (!result._0) {
    throw new Error(`Invalid vector ID: "${input}"`);
  }
  return { hi: result._1, lo: result._2 };
}

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

function jsonResponse(data: unknown, status: number = 200): Response {
  return Response.json(data, { status, headers: CORS_HEADERS });
}

function errorResponse(message: string, status: number = 500): Response {
  return jsonResponse({ error: message }, status);
}

export default {
  async fetch(request: Request, env: Bindings): Promise<Response> {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    const url = new URL(request.url);
    const path = url.pathname;

    try {
      const { ffi: vcdb, router: r } = await ensureInitialized();

      // POST /upsert — { points: [{ id: "123", vector, payload }] }
      if (request.method === "POST" && path === "/upsert") {
        const body = (await request.json()) as {
          points: {
            id: string;
            vector: number[];
            payload: Record<string, unknown>;
          }[];
        };
        const points = body.points.map((p) => ({
          id: parseId(vcdb, p.id),
          vector: p.vector,
          payload: p.payload,
        }));
        await r.upsert(env, points);
        return jsonResponse({ status: "ok", count: points.length });
      }

      // POST /search — { vector, topK?, filter? }
      if (request.method === "POST" && path === "/search") {
        const body = (await request.json()) as {
          vector: number[];
          topK?: number;
          filter?: string;
        };
        const hits = await r.search(
          env,
          body.vector,
          body.topK ?? 10,
          body.filter,
        );
        return jsonResponse({ results: hits });
      }

      // GET /vectors/:id
      const getMatch = path.match(/^\/vectors\/([^/]+)$/);
      if (request.method === "GET" && getMatch) {
        const id = parseId(vcdb, getMatch[1]);
        const result = await r.get(env, id);
        if (!result) return errorResponse("Not found", 404);
        return jsonResponse(result);
      }

      // POST /scroll — { filter?, offset?: "123", limit? }
      if (request.method === "POST" && path === "/scroll") {
        const body = (await request.json()) as {
          filter?: string;
          offset?: string;
          limit?: number;
        };
        const offset: MbInt64 | undefined =
          body.offset !== undefined ? parseId(vcdb, body.offset) : undefined;
        const results = await r.scrollFiltered(
          env,
          body.filter ?? "",
          offset,
          body.limit ?? 100,
        );
        return jsonResponse({ results });
      }

      // POST /count — { filter }
      if (request.method === "POST" && path === "/count") {
        const body = (await request.json()) as { filter: string };
        const count = await r.countFiltered(env, body.filter);
        return jsonResponse({ count });
      }

      // GET /health
      if (
        request.method === "GET" &&
        (path === "/health" || path === "/healthz")
      ) {
        return jsonResponse({
          status: "ok",
          shards: r.shardCount,
        });
      }

      return errorResponse("Not found", 404);
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      const status = message.startsWith("Invalid vector ID") ? 400 : 500;
      if (status === 500) console.error("Worker error:", e);
      return errorResponse(message, status);
    }
  },
};
