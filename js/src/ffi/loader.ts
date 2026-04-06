/**
 * @file MoonBit module loader.
 *
 * Loads the compiled MoonBit JS module once and provides typed
 * accessors for each FFI slice. Consumers import the slice they need:
 *
 *   import { getVectorDbFfi } from "../ffi/loader.js";
 *   const ffi = getVectorDbFfi();
 *
 * The full WasmModule is never exposed beyond this file.
 */
import type {
  WasmModule,
  VectorDbFfi,
  GatewayFfi,
  PersistentFfi,
  DistributedFfi,
} from "./types.js";

let module: WasmModule | null = null;
const DEFAULT_LIB_PATH = "./lib.js";

/**
 * Load the MoonBit JS module.
 *
 * Accepts either a path string (dynamic import) or a pre-loaded
 * module object (for testing / custom bundling).
 *
 * Idempotent — subsequent calls are no-ops.
 */
export async function loadModule(
  moduleOrPath?: string | Record<string, unknown>,
): Promise<void> {
  if (module) return;
  if (typeof moduleOrPath === "object" && moduleOrPath !== null) {
    module = moduleOrPath as unknown as WasmModule;
    return;
  }
  const path = moduleOrPath ?? DEFAULT_LIB_PATH;
  const mod = await import(path);
  module = mod as unknown as WasmModule;
}

/** Whether the module has been loaded. */
export function isModuleLoaded(): boolean {
  return module !== null;
}

/* ── Slice accessors ─────────────────────────────────────────── */

function assertLoaded(): WasmModule {
  if (!module) {
    throw new Error("MoonBit module not loaded. Call loadModule() first.");
  }
  return module;
}

export function getVectorDbFfi(): VectorDbFfi {
  return assertLoaded();
}

export function getGatewayFfi(): GatewayFfi {
  return assertLoaded();
}

export function getPersistentFfi(): PersistentFfi {
  return assertLoaded();
}

export function getDistributedFfi(): DistributedFfi {
  return assertLoaded();
}
