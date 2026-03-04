#!/usr/bin/env node
/**
 * vcdb HTTP Server
 *
 * Thin HTTP layer over MoonBit gateway implementation.
 * All business logic is handled by the WASM gateway.
 * Storage is handled via Storage trait callbacks - when --storage is provided,
 * filesystem callbacks are registered so WASM writes directly to disk.
 */

import { Hono } from "hono";
import { cors } from "hono/cors";
import { serve } from "@hono/node-server";
import {
  loadWasm,
  gatewayRequest,
  registerStorageCallbacks,
  StorageKind,
  type GatewayResponse,
  type StorageCallbacks,
  type StorageKindType,
} from "./wasm/vcdb.js";
import * as fs from "node:fs";
import * as path from "node:path";

/**
 * Get subdirectory name for each storage kind
 */
function kindToDir(kind: StorageKindType): string {
  switch (kind) {
    case StorageKind.Config:
      return "config";
    case StorageKind.Index:
      return "index";
    case StorageKind.Data:
      return "data";
    default:
      return "data";
  }
}

// ============================================================================
// Filesystem Storage Callbacks
// ============================================================================

/**
 * Create filesystem storage callbacks for a given base path.
 * These callbacks are registered with the WASM gateway so all storage
 * operations go directly to the filesystem.
 */
function createFilesystemStorage(basePath: string): StorageCallbacks {
  // Ensure base directory exists
  if (!fs.existsSync(basePath)) {
    fs.mkdirSync(basePath, { recursive: true });
  }

  // Helper to get full path with kind-based subdirectory
  const getFullPath = (filePath: string, kind: StorageKindType): string => {
    return path.join(basePath, kindToDir(kind), filePath);
  };

  return {
    read: (filePath: string, kind: StorageKindType): Uint8Array => {
      const fullPath = getFullPath(filePath, kind);
      if (!fs.existsSync(fullPath)) {
        return new Uint8Array(0);
      }
      return new Uint8Array(fs.readFileSync(fullPath));
    },

    write: (filePath: string, data: Uint8Array, kind: StorageKindType): void => {
      const fullPath = getFullPath(filePath, kind);
      const dir = path.dirname(fullPath);
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }
      fs.writeFileSync(fullPath, data);
    },

    exists: (filePath: string, kind: StorageKindType): boolean => {
      const fullPath = getFullPath(filePath, kind);
      return fs.existsSync(fullPath);
    },

    del: (filePath: string, kind: StorageKindType): void => {
      const fullPath = getFullPath(filePath, kind);
      if (fs.existsSync(fullPath)) {
        fs.unlinkSync(fullPath);
      }
    },

    list: (kind: StorageKindType): string[] => {
      const kindDir = path.join(basePath, kindToDir(kind));
      const files: string[] = [];
      const walk = (dir: string, prefix: string) => {
        if (!fs.existsSync(dir)) return;
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
          const relativePath = prefix ? `${prefix}/${entry.name}` : entry.name;
          if (entry.isDirectory()) {
            walk(path.join(dir, entry.name), relativePath);
          } else {
            files.push(relativePath);
          }
        }
      };
      walk(kindDir, "");
      return files;
    },
  };
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

    // No manual sync needed - storage callbacks handle persistence directly

    return formatResponse(c, response);
  });

  return app;
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

  // Register filesystem storage callbacks if --storage is provided
  if (config.storage) {
    const storagePath = config.storage;
    const callbacks = createFilesystemStorage(storagePath);
    registerStorageCallbacks(callbacks);
    console.log(`Storage: filesystem (${storagePath})`);
  } else {
    console.log("Storage: in-memory (no persistence)");
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
