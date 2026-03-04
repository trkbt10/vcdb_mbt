#!/usr/bin/env node
/**
 * vcdb HTTP Server
 *
 * Thin HTTP layer over MoonBit gateway implementation.
 * Uses CachedStorage for async storage with WASM compatibility.
 */

import { Hono } from "hono";
import { cors } from "hono/cors";
import { serve } from "@hono/node-server";
import {
  loadWasm,
  gatewayRequest,
  registerStorageCallbacks,
  type GatewayResponse,
} from "./wasm/vcdb.js";
import { createNodeStorage } from "./storage/node.js";
import { CachedStorage } from "./storage/wasm-bridge.js";

let cachedStorage: CachedStorage | null = null;

// ============================================================================
// App
// ============================================================================

function createApp() {
  const app = new Hono();

  app.use("*", cors());

  app.all("*", async (c) => {
    const method = c.req.method;
    const url = new URL(c.req.url);
    const pathSegments = url.pathname.split("/").filter((s) => s.length > 0);

    let body = "";
    if (method === "POST" || method === "PUT") {
      try {
        body = await c.req.text();
      } catch {
        // empty body is ok
      }
    }

    const response = gatewayRequest(method, pathSegments, body);

    // Flush after mutations
    if (cachedStorage?.hasDirty()) {
      await cachedStorage.flush();
    }

    return formatResponse(c, response);
  });

  return app;
}

function formatResponse(
  c: { json: (data: unknown, status?: number) => Response },
  response: GatewayResponse
): Response {
  if (response.status === "error") {
    const statusCode = getErrorStatusCode(response.error ?? "");
    return c.json({ error: response.error }, statusCode);
  }

  const result = response.result;

  if (result === true) {
    return c.json({ status: "ok" });
  }

  if (typeof result === "object" && result !== null && "status" in result) {
    return c.json(result);
  }

  return c.json(result);
}

function getErrorStatusCode(error: string): number {
  if (error.includes("not found") || error.includes("Not found")) {
    return 404;
  }
  if (error.includes("already exists")) {
    return 400;
  }
  if (error.includes("Dimension mismatch") || error.includes("Invalid")) {
    return 400;
  }
  return 500;
}

// ============================================================================
// CLI
// ============================================================================

function parseArgs(args: string[]) {
  const config: { port: number; host: string; storage: string | null } = {
    port: 6333,
    host: "0.0.0.0",
    storage: null,
  };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--port" && args[i + 1]) {
      config.port = parseInt(args[i + 1], 10);
      i++;
    } else if (args[i] === "--host" && args[i + 1]) {
      config.host = args[i + 1];
      i++;
    } else if (args[i] === "--storage" && args[i + 1]) {
      config.storage = args[i + 1];
      i++;
    }
  }
  return config;
}

async function main() {
  const args = process.argv.slice(2);
  const config = parseArgs(args);

  console.log("vcdb HTTP Server");

  if (!config.storage) {
    throw new Error("--storage <path> is required");
  }

  console.log("Loading WASM module...");
  await loadWasm();

  console.log("Loading data from storage...");
  const adapter = createNodeStorage({ baseDir: config.storage });
  cachedStorage = new CachedStorage({ adapter });
  await cachedStorage.prefetch();

  registerStorageCallbacks(cachedStorage.getCallbacks());
  console.log(`Storage: ${config.storage}`);

  const app = createApp();

  // Graceful shutdown
  const shutdown = async () => {
    console.log("\nShutting down...");
    if (cachedStorage) {
      await cachedStorage.close();
    }
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);

  console.log(`Server running at http://${config.host}:${config.port}`);

  serve({
    fetch: app.fetch,
    port: config.port,
    hostname: config.host,
  });
}

main().catch(console.error);
