/**
 * @file High-level persistent VectorDB client.
 *
 * Wraps PersistentFfi with JS-idiomatic types:
 *   - VectorId as bigint (not hi/lo pairs)
 *   - JSON payload serialization
 *   - MoonBit tuple decoding
 *
 * Consumers never deal with MoonBit encoding directly.
 */
import type { PersistentFfi } from "./ffi/types.js";
import type { VectorId, SearchHit, PointRecord, ScrollEntry } from "./types.js";
import { toHiLo, fromHiLo, nowNs } from "./ffi/vector-id.js";

const parsePayload = (json: string): Record<string, unknown> | null => {
  if (!json) return null;
  try {
    return JSON.parse(json) as Record<string, unknown>;
  } catch {
    return null;
  }
};

/**
 * High-level wrapper over PersistentFfi for a single instance.
 *
 * All MoonBit-specific encoding (tuples, hi/lo IDs, JSON serialization)
 * is handled here. Consumers work with bigint IDs and plain JS objects.
 */
export class PersistentDB {
  constructor(
    private readonly ffi: PersistentFfi,
    private readonly instanceId: number,
  ) {}

  /* ── Mutations (async — WAL I/O) ───────────────────────────── */

  async upsert(
    points: readonly {
      id: VectorId;
      vector: number[];
      payload: Record<string, unknown>;
    }[],
  ): Promise<void> {
    const ffiPoints = points.map((p) => {
      const { hi, lo } = toHiLo(p.id);
      return { _0: hi, _1: lo, _2: p.vector, _3: JSON.stringify(p.payload) };
    });
    await this.ffi.persistent_upsert(this.instanceId, ffiPoints, nowNs());
  }

  async remove(id: VectorId): Promise<boolean> {
    const { hi, lo } = toHiLo(id);
    return this.ffi.persistent_remove(this.instanceId, hi, lo, nowNs());
  }

  async updateAttrs(
    id: VectorId,
    attrs: Record<string, unknown>,
  ): Promise<boolean> {
    const { hi, lo } = toHiLo(id);
    return this.ffi.persistent_update_attrs(
      this.instanceId, hi, lo, JSON.stringify(attrs), nowNs(),
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
      id: fromHiLo(r._0, r._1),
      score: r._2,
      payload: parsePayload(r._3),
    }));
  }

  get(id: VectorId): PointRecord {
    const { hi, lo } = toHiLo(id);
    const r = this.ffi.persistent_get(this.instanceId, hi, lo, true);
    return {
      found: r._0,
      vector: r._1,
      payload: r._0 ? parsePayload(r._2) : null,
    };
  }

  has(id: VectorId): boolean {
    const { hi, lo } = toHiLo(id);
    return this.ffi.persistent_has(this.instanceId, hi, lo);
  }

  scroll(
    offset: VectorId | undefined,
    limit: number,
  ): readonly ScrollEntry[] {
    const hasOffset = offset !== undefined;
    const { hi: oHi, lo: oLo } = hasOffset ? toHiLo(offset) : { hi: 0, lo: 0 };
    const results = this.ffi.persistent_scroll(
      this.instanceId, oHi, oLo, hasOffset, limit, true,
    );
    return results.map((r) => ({
      id: fromHiLo(r._0, r._1),
      payload: parsePayload(r._2),
    }));
  }

  scrollFiltered(
    filterJson: string,
    offset: VectorId | undefined,
    limit: number,
  ): readonly ScrollEntry[] {
    const hasOffset = offset !== undefined;
    const { hi: oHi, lo: oLo } = hasOffset ? toHiLo(offset) : { hi: 0, lo: 0 };
    const results = this.ffi.persistent_scroll_filtered(
      this.instanceId, filterJson, oHi, oLo, hasOffset, limit, true,
    );
    return results.map((r) => ({
      id: fromHiLo(r._0, r._1),
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
