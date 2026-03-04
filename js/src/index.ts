/**
 * @vcdb/server - Vector database server package
 *
 * Main entry point exports only the core public API.
 * For specific modules, use subpath imports:
 *
 * - `@vcdb/server/storage` - Storage backends (memory, node, indexeddb, etc.)
 * - `@vcdb/server/wasm` - MoonBit WASM VectorDB
 */

// Only export the FileIO interface type - users import implementations from subpaths
export type { FileIO } from "./storage/types.js";
