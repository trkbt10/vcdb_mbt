#!/usr/bin/env node
/**
 * vcdb HTTP Server
 *
 * Thin HTTP layer over MoonBit gateway implementation.
 * All business logic is handled by the WASM gateway.
 * Storage sync is handled via gateway storage API.
 */

import { Hono } from "hono";
import { cors } from "hono/cors";
import { serve } from "@hono/node-server";
import {
  loadWasm,
  gatewayRequest,
  gatewayStorageList,
  gatewayStorageRead,
  type GatewayResponse,
} from "./wasm/vcdb.js";
import * as fs from "node:fs";
import * as path from "node:path";

// ============================================================================
// Storage Sync - syncs WASM MemoryStorage to disk
// ============================================================================

let storagePath: string | null = null;

/**
 * Sync gateway storage to disk.
 * Called after mutations to persist changes.
 */
function syncStorageToDisk(): void {
  if (!storagePath) return;

  const files = gatewayStorageList();
  for (const file of files) {
    const data = gatewayStorageRead(file);
    if (data.length === 0) continue;

    const fullPath = path.join(storagePath, file);
    const dir = path.dirname(fullPath);

    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }

    fs.writeFileSync(fullPath, data);
  }
}

// ============================================================================
// App
// ============================================================================

function createApp() {
  const app = new Hono();

  // CORS
  app.use("*", cors());

  // Catch-all handler that delegates to gateway
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

    // Sync storage after successful mutations
    if (response.status === "ok" && isMutation(method, pathSegments)) {
      syncStorageToDisk();
    }

    return formatResponse(c, response);
  });

  return app;
}

/**
 * Check if the request is a mutation that needs persistence
 */
function isMutation(method: string, path: string[]): boolean {
  if (method === "POST" || method === "PUT" || method === "DELETE") {
    // All collection/point operations
    return path[0] === "collections";
  }
  return false;
}

/**
 * Format gateway response as HTTP response.
 * Converts gateway's internal format to REST-compatible format.
 */
function formatResponse(
  c: { json: (data: unknown, status?: number) => Response },
  response: GatewayResponse
): Response {
  if (response.status === "error") {
    const statusCode = getErrorStatusCode(response.error ?? "");
    return c.json({ error: response.error }, statusCode);
  }

  // Unwrap the result for cleaner API
  const result = response.result;

  // Handle boolean results (true -> {status: "ok"})
  if (result === true) {
    return c.json({ status: "ok" });
  }

  // Handle objects with status/upserted (upsert response)
  if (typeof result === "object" && result !== null && "status" in result) {
    return c.json(result);
  }

  // Return result directly
  return c.json(result);
}

/**
 * Map error messages to HTTP status codes.
 */
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
  console.log("Loading WASM module...");

  await loadWasm();

  if (config.storage) {
    storagePath = config.storage;
    if (!fs.existsSync(storagePath)) {
      fs.mkdirSync(storagePath, { recursive: true });
    }
    console.log(`Storage path: ${storagePath}`);
  }

  const app = createApp();

  console.log(`Server running at http://${config.host}:${config.port}`);

  serve({
    fetch: app.fetch,
    port: config.port,
    hostname: config.host,
  });
}

main().catch(console.error);
