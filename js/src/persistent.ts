/**
 * @file High-level persistent VectorDB client for JS consumers.
 *
 * Wraps the persistent_* FFI with JS-idiomatic types:
 *   - MbInt64 (hi/lo i32 pairs) for vector IDs and timestamps
 *   - JSON payload ↔ string serialization
 *   - MoonBit tuples (._0, ._1) ↔ named objects
 *   - Timestamp generation
 *
 * Consumers should never deal with MoonBit tuple encoding directly.
 * This is the single place where FFI result shapes are interpreted.
 */
import type { MbInt64, PersistentFFI } from "./storage/persistent-bridge.js";

/* ── Public result types ─────────────────────────────────────── */

export type SearchHit = {
  readonly id: MbInt64;
  readonly score: number;
  readonly payload: Record<string, unknown> | null;
};

export type PointRecord = {
  readonly found: boolean;
  readonly vector: number[];
  readonly payload: Record<string, unknown> | null;
};

export type ScrollEntry = {
  readonly id: MbInt64;
  readonly payload: Record<string, unknown> | null;
};

/* ── Internal helpers ────────────────────────────────────────── */

/** Current time as MoonBit Int64 nanoseconds since epoch. */
const nowNs = (): MbInt64 => {
  const ms = Date.now();
  const ns = ms * 1_000_000;
  return { hi: Math.floor(ns / 0x100000000), lo: ns >>> 0 };
};

const parsePayload = (json: string): Record<string, unknown> | null => {
  if (!json) return null;
  try {
    return JSON.parse(json) as Record<string, unknown>;
  } catch {
    return null;
  }
};

/* ── PersistentDB class ──────────────────────────────────────── */

/**
 * High-level wrapper over persistent_* FFI for a single instance.
 *
 * All MoonBit-specific encoding (tuples, hi/lo IDs, JSON serialization)
 * is handled here. Consumers work with plain JS objects.
 */
export class PersistentDB {
  constructor(
    private readonly ffi: PersistentFFI,
    private readonly instanceId: number,
  ) {}

  /* ── Mutations (async — WAL I/O) ───────────────────────────── */

  async upsert(
    points: readonly {
      id: MbInt64;
      vector: number[];
      payload: Record<string, unknown>;
    }[],
  ): Promise<void> {
    const ffiPoints = points.map((p) => ({
      _0: p.id.hi,
      _1: p.id.lo,
      _2: p.vector,
      _3: JSON.stringify(p.payload),
    }));
    await this.ffi.persistent_upsert(this.instanceId, ffiPoints, nowNs());
  }

  async remove(id: MbInt64): Promise<boolean> {
    return this.ffi.persistent_remove(
      this.instanceId, id.hi, id.lo, nowNs(),
    );
  }

  async updateAttrs(
    id: MbInt64,
    attrs: Record<string, unknown>,
  ): Promise<boolean> {
    return this.ffi.persistent_update_attrs(
      this.instanceId, id.hi, id.lo, JSON.stringify(attrs), nowNs(),
    );
  }

  async checkpoint(): Promise<void> {
    await this.ffi.persistent_checkpoint(this.instanceId);
  }

  async compact(): Promise<number> {
    return this.ffi.persistent_compact(this.instanceId);
  }

  /* ── Reads (synchronous — in-memory) ───────────────────────── */

  search(
    vector: number[],
    topK: number,
    filterJson: string = "",
  ): readonly SearchHit[] {
    const results = this.ffi.persistent_search(
      this.instanceId, vector, topK, true, filterJson,
    );
    return results.map((r) => ({
      id: { hi: r._0, lo: r._1 },
      score: r._2,
      payload: parsePayload(r._3),
    }));
  }

  get(id: MbInt64): PointRecord {
    const r = this.ffi.persistent_get(
      this.instanceId, id.hi, id.lo, true,
    );
    return {
      found: r._0,
      vector: r._1,
      payload: r._0 ? parsePayload(r._2) : null,
    };
  }

  has(id: MbInt64): boolean {
    return this.ffi.persistent_has(this.instanceId, id.hi, id.lo);
  }

  scroll(
    offset: MbInt64 | undefined,
    limit: number,
  ): readonly ScrollEntry[] {
    const hasOffset = offset !== undefined;
    const results = this.ffi.persistent_scroll(
      this.instanceId,
      offset?.hi ?? 0,
      offset?.lo ?? 0,
      hasOffset,
      limit,
      true,
    );
    return results.map((r) => ({
      id: { hi: r._0, lo: r._1 },
      payload: parsePayload(r._2),
    }));
  }

  scrollFiltered(
    filterJson: string,
    offset: MbInt64 | undefined,
    limit: number,
  ): readonly ScrollEntry[] {
    const hasOffset = offset !== undefined;
    const results = this.ffi.persistent_scroll_filtered(
      this.instanceId,
      filterJson,
      offset?.hi ?? 0,
      offset?.lo ?? 0,
      hasOffset,
      limit,
      true,
    );
    return results.map((r) => ({
      id: { hi: r._0, lo: r._1 },
      payload: parsePayload(r._2),
    }));
  }

  countFiltered(filterJson: string): number {
    return this.ffi.persistent_count_filtered(this.instanceId, filterJson);
  }

  /* ── Diagnostics ───────────────────────────────────────────── */

  size(): number {
    return this.ffi.persistent_db_size(this.instanceId);
  }

  rawSize(): number {
    return this.ffi.persistent_db_raw_size(this.instanceId);
  }

  dim(): number {
    return this.ffi.persistent_db_dim(this.instanceId);
  }
}
