/**
 * @file Cloudflare Worker entry point — Durable Objects example.
 *
 * Demonstrates a production-grade vcdb deployment with:
 * - Sharded Durable Objects for horizontal scaling
 * - WAL + R2 persistence for crash recovery
 * - Scatter-gather search across shards
 *
 * Based on production patterns from usbkr.
 */
import { createShardRouter, type ShardRouter } from "./infra/shard-router.ts";
import type { VcdbId, Bindings, VcdbPoint } from "./types.ts";
import { numericToId } from "./types.ts";

export { VcdbStore } from "./infra/vcdb-do.ts";

const router: ShardRouter = createShardRouter(8);

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
      // POST /upsert — { points: [{ id, vector, payload }] }
      if (request.method === "POST" && path === "/upsert") {
        const body = (await request.json()) as {
          points: { id: number; vector: number[]; payload: Record<string, unknown> }[];
        };
        const points: VcdbPoint[] = body.points.map((p) => ({
          id: numericToId(p.id),
          vector: p.vector,
          payload: p.payload,
        }));
        await router.upsert(env, points);
        return jsonResponse({ status: "ok", count: points.length });
      }

      // POST /search — { vector, topK?, filter? }
      if (request.method === "POST" && path === "/search") {
        const body = (await request.json()) as {
          vector: number[];
          topK?: number;
          filter?: string;
        };
        const hits = await router.search(
          env,
          body.vector,
          body.topK ?? 10,
          body.filter,
        );
        return jsonResponse({ results: hits });
      }

      // GET /vectors/:id
      const getMatch = path.match(/^\/vectors\/(\d+)$/);
      if (request.method === "GET" && getMatch) {
        const id = numericToId(parseInt(getMatch[1], 10));
        const result = await router.get(env, id);
        if (!result) return errorResponse("Not found", 404);
        return jsonResponse(result);
      }

      // POST /scroll — { filter?, offset?, limit? }
      if (request.method === "POST" && path === "/scroll") {
        const body = (await request.json()) as {
          filter?: string;
          offset?: number;
          limit?: number;
        };
        const offset: VcdbId | undefined =
          body.offset !== undefined ? numericToId(body.offset) : undefined;
        const results = await router.scrollFiltered(
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
        const count = await router.countFiltered(env, body.filter);
        return jsonResponse({ count });
      }

      // GET /health
      if (request.method === "GET" && (path === "/health" || path === "/healthz")) {
        return jsonResponse({
          status: "ok",
          shards: router.shardCount,
        });
      }

      return errorResponse("Not found", 404);
    } catch (e) {
      console.error("Worker error:", e);
      return errorResponse(String(e));
    }
  },
};
