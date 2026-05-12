// @vcdb/vcdb-features — vcdb-aware React features that combine db-viewer +
// ui-kit with vcdb-specific concepts (HNSW/IVF tuning, storage adapters,
// collection registry, dashboard server config).

// Stable entry points. Subpath exports (`@vcdb/vcdb-features/wizard` etc.)
// exist for additional features whose typecheck is not yet wired up — see
// tsconfig.json `include` for the verified surface.

export { DatabaseProvider, useDatabase } from "./context/index.ts";
export { useKeyboard, SHORTCUTS } from "./hooks/index.ts";
export { RegistryProvider, useRegistry } from "./registry/hooks/useRegistry.tsx";

export { ExplorerPage } from "./explorer/index.ts";
export { ConnectionManager } from "./registry/components/index.ts";
export type { DatabaseInfo } from "./registry/components/index.ts";
