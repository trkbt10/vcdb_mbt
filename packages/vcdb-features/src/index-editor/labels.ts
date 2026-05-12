/**
 * @file Display helpers for vcdb IndexConfig kinds.
 *
 * Single source of truth for "given an index config / kind, how do we
 * present it to the user?" — both the wizard (creation) and the explorer
 * (post-creation listing) consume from here. Adding a new index kind
 * means updating this one file.
 */

import type { IndexConfig } from "vcdb/meta/index-types";

type VectorKind = "hnsw" | "ivf" | "bruteforce";
type AttrKind = "bptree" | "lsm" | "bitmap" | "basic";

/** Friendly vector-index label, e.g. "HNSW". Falls back to the kind itself. */
export function getVectorKindLabel(kind: string): string {
  switch (kind as VectorKind) {
    case "hnsw":
      return "HNSW";
    case "ivf":
      return "IVF";
    case "bruteforce":
      return "Bruteforce";
    default:
      return kind;
  }
}

/** Friendly attribute-index label, e.g. "B+Tree". */
export function getAttrKindLabel(kind: string): string {
  switch (kind as AttrKind) {
    case "bptree":
      return "B+Tree";
    case "lsm":
      return "LSM";
    case "bitmap":
      return "Bitmap";
    case "basic":
      return "Basic";
    default:
      return kind;
  }
}

/** Category bucket: "Vector" / "Attribute" / "Combined" / "Unknown". */
export function getIndexCategory(kind: IndexConfig["kind"]): string {
  switch (kind) {
    case "bruteforce":
    case "hnsw":
    case "ivf":
      return "Vector";
    case "basic":
    case "bitmap":
    case "bptree":
    case "lsm":
      return "Attribute";
    case "combined":
      return "Combined";
    default:
      return "Unknown";
  }
}

/** Emoji icon for an index kind, used by card-style listings. */
export function getIndexIcon(kind: IndexConfig["kind"]): string {
  switch (getIndexCategory(kind)) {
    case "Vector":
      return "🔍";
    case "Attribute":
      return "🏷️";
    case "Combined":
      return "⚡";
    default:
      return "📦";
  }
}

/**
 * Composite label for an IndexConfig, suitable for table cells / chips:
 *   - "HNSW"
 *   - "B+Tree"
 *   - "HNSW + B+Tree" (combined)
 */
export function getIndexTypeLabel(config: IndexConfig): string {
  switch (config.kind) {
    case "hnsw":
    case "ivf":
    case "bruteforce":
      return getVectorKindLabel(config.kind);
    case "bptree":
    case "lsm":
    case "bitmap":
    case "basic":
      return getAttrKindLabel(config.kind);
    case "combined":
      return `${getVectorKindLabel(config.vector.kind)} + ${getAttrKindLabel(config.attribute.kind)}`;
    default:
      return "Unknown";
  }
}

/**
 * Verbose one-line description used by the wizard's index card, e.g.
 * "HNSW vector index (cosine), M=16".
 */
export function getIndexDescription(config: IndexConfig): string {
  switch (config.kind) {
    case "bruteforce":
      return `Bruteforce vector search${config.metric ? ` (${config.metric})` : ""}`;
    case "hnsw":
      return `HNSW vector index${config.metric ? ` (${config.metric})` : ""}${config.M ? `, M=${config.M}` : ""}`;
    case "ivf":
      return `IVF vector index${config.metric ? ` (${config.metric})` : ""}${config.nlist ? `, nlist=${config.nlist}` : ""}`;
    case "basic":
      return "Basic attribute index (hash-based)";
    case "bitmap":
      return "Bitmap attribute index";
    case "bptree":
      return `B+ Tree attribute index${config.order ? ` (order=${config.order})` : ""}`;
    case "lsm":
      return `LSM Tree attribute index${config.order ? ` (order=${config.order})` : ""}`;
    case "combined":
      return `Combined: ${config.vector.kind.toUpperCase()} + ${config.attribute.kind.toUpperCase()}${config.execution ? ` (${config.execution})` : ""}`;
    default:
      return "Unknown index type";
  }
}

/**
 * Compact one-liner used by the wizard's review step:
 *   - "HNSW (cosine, M=16)"
 *   - "Combined: HNSW + BPTREE (auto)"
 */
export function getIndexSummary(config: IndexConfig): string {
  switch (config.kind) {
    case "bruteforce":
      return `Bruteforce (${config.metric ?? "cosine"})`;
    case "hnsw":
      return `HNSW (${config.metric ?? "cosine"}, M=${config.M ?? 16})`;
    case "ivf":
      return `IVF (${config.metric ?? "cosine"}, nlist=${config.nlist ?? 64})`;
    case "basic":
      return "Basic (hash)";
    case "bitmap":
      return "Bitmap";
    case "bptree":
      return `B+ Tree (order=${config.order ?? "declared"})`;
    case "lsm":
      return `LSM (order=${config.order ?? "declared"})`;
    case "combined":
      return `Combined: ${config.vector.kind.toUpperCase()} + ${config.attribute.kind.toUpperCase()} (${config.execution ?? "auto"})`;
    default:
      return "Unknown";
  }
}
