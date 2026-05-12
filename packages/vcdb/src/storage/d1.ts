/**
 * @file Cloudflare D1 storage adapter for vcdb.
 *
 * Implements DOKeyValueStore using D1 (SQLite) as a KVS.
 * Large values are chunked to stay within D1's row size limits.
 *
 * D1 advantages over R2 for snapshot storage:
 * - Lower latency for small-to-medium values (in-region SQLite)
 * - Atomic batch writes via transactions
 * - No cold-start penalty (always warm within the same colo)
 *
 * Schema (auto-created on first use):
 *   CREATE TABLE IF NOT EXISTS vcdb_kv (
 *     key TEXT PRIMARY KEY,
 *     data BLOB NOT NULL,
 *     size INTEGER NOT NULL,
 *     updated_at INTEGER NOT NULL DEFAULT (unixepoch())
 *   );
 */
import type { DOKeyValueStore } from "./do-kv.js";

/**
 * Minimal D1 database interface — matches Cloudflare Workers D1Database
 * without requiring @cloudflare/workers-types.
 */
export interface D1DatabaseLike {
  prepare(query: string): D1PreparedStatementLike;
  batch<T = unknown>(statements: D1PreparedStatementLike[]): Promise<D1ResultLike<T>[]>;
  exec(query: string): Promise<unknown>;
}

export interface D1PreparedStatementLike {
  bind(...values: unknown[]): D1PreparedStatementLike;
  first<T = unknown>(column?: string): Promise<T | null>;
  all<T = unknown>(): Promise<D1ResultLike<T>>;
  run(): Promise<D1ResultLike>;
}

export interface D1ResultLike<T = unknown> {
  results: T[];
  success: boolean;
  meta?: unknown;
}

export interface D1KeyValueStoreOptions {
  /** D1 database binding (env.MY_DB). */
  db: D1DatabaseLike;
  /**
   * Table name. Default "vcdb_kv".
   * Use different table names to isolate multiple stores in one D1 database.
   */
  tableName?: string;
  /**
   * Optional key prefix for namespace isolation.
   * All keys are stored as `${keyPrefix}${path}`.
   */
  keyPrefix?: string;
}

/** Chunk size: 900KB to stay well under D1's 1MB row limit. */
const CHUNK_SIZE = 900_000;

/**
 * Create a D1-backed key-value store implementing DOKeyValueStore.
 *
 * The table is auto-created on first prefetch() call.
 */
export function createD1KeyValueStore(
  options: D1KeyValueStoreOptions,
): DOKeyValueStore {
  const { db, tableName = "vcdb_kv", keyPrefix = "" } = options;
  const key = (path: string): string => keyPrefix + path;
  let initialized = false;

  const ensureTable = async (): Promise<void> => {
    if (initialized) return;
    await db.exec(`CREATE TABLE IF NOT EXISTS ${tableName} (key TEXT PRIMARY KEY, data BLOB NOT NULL, size INTEGER NOT NULL, updated_at INTEGER NOT NULL DEFAULT (unixepoch()))`);
    initialized = true;
  };

  /** Number of chunks for a given base key (0 = single value, N = N chunks). */
  const chunkCount = (dataLength: number): number =>
    dataLength <= CHUNK_SIZE ? 0 : Math.ceil(dataLength / CHUNK_SIZE);

  const chunkKey = (base: string, index: number): string =>
    `${base}::chunk::${index}`;

  return {
    async prefetch() {
      await ensureTable();
    },

    async read(path) {
      await ensureTable();
      const k = key(path);

      // Try single-value read first
      const row = await db.prepare(
        `SELECT data, size FROM ${tableName} WHERE key = ?`,
      ).bind(k).first<{ data: ArrayBuffer; size: number }>();

      if (!row) return null;

      // If size matches the blob, it's a single value
      const singleData = new Uint8Array(row.data);
      if (singleData.length === row.size) {
        return singleData;
      }

      // It's the meta entry — read chunks
      const numChunks = row.size;
      const parts: Uint8Array[] = [];
      for (let i = 0; i < numChunks; i++) {
        const chunk = await db.prepare(
          `SELECT data FROM ${tableName} WHERE key = ?`,
        ).bind(chunkKey(k, i)).first<{ data: ArrayBuffer }>();
        if (!chunk) return null;
        parts.push(new Uint8Array(chunk.data));
      }

      const total = parts.reduce((s, p) => s + p.length, 0);
      const result = new Uint8Array(total);
      let offset = 0;
      for (const part of parts) {
        result.set(part, offset);
        offset += part.length;
      }
      return result;
    },

    async write(path, data) {
      await ensureTable();
      const k = key(path);

      // Delete old chunks if any
      await db.prepare(
        `DELETE FROM ${tableName} WHERE key = ? OR key LIKE ?`,
      ).bind(k, `${k}::chunk::%`).run();

      const chunks = chunkCount(data.length);
      if (chunks === 0) {
        // Single value
        const buf = data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
        await db.prepare(
          `INSERT OR REPLACE INTO ${tableName} (key, data, size) VALUES (?, ?, ?)`,
        ).bind(k, buf, data.length).run();
      } else {
        // Chunked: write meta + chunks in a batch
        const stmts: D1PreparedStatementLike[] = [];

        // Meta entry: data is empty blob, size is chunk count
        stmts.push(
          db.prepare(
            `INSERT OR REPLACE INTO ${tableName} (key, data, size) VALUES (?, ?, ?)`,
          ).bind(k, new ArrayBuffer(0), chunks),
        );

        for (let i = 0; i < chunks; i++) {
          const start = i * CHUNK_SIZE;
          const end = Math.min(start + CHUNK_SIZE, data.length);
          const slice = data.slice(start, end);
          const buf = slice.buffer.slice(slice.byteOffset, slice.byteOffset + slice.byteLength);
          stmts.push(
            db.prepare(
              `INSERT OR REPLACE INTO ${tableName} (key, data, size) VALUES (?, ?, ?)`,
            ).bind(chunkKey(k, i), buf, slice.length),
          );
        }

        await db.batch(stmts);
      }
    },

    async writeAtomic(entries) {
      await ensureTable();
      const stmts: D1PreparedStatementLike[] = [];

      for (const { path: p, data } of entries) {
        const k = key(p);

        // Delete old
        stmts.push(
          db.prepare(
            `DELETE FROM ${tableName} WHERE key = ? OR key LIKE ?`,
          ).bind(k, `${k}::chunk::%`),
        );

        const chunks = chunkCount(data.length);
        if (chunks === 0) {
          const buf = data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
          stmts.push(
            db.prepare(
              `INSERT OR REPLACE INTO ${tableName} (key, data, size) VALUES (?, ?, ?)`,
            ).bind(k, buf, data.length),
          );
        } else {
          stmts.push(
            db.prepare(
              `INSERT OR REPLACE INTO ${tableName} (key, data, size) VALUES (?, ?, ?)`,
            ).bind(k, new ArrayBuffer(0), chunks),
          );
          for (let i = 0; i < chunks; i++) {
            const start = i * CHUNK_SIZE;
            const end = Math.min(start + CHUNK_SIZE, data.length);
            const slice = data.slice(start, end);
            const buf = slice.buffer.slice(slice.byteOffset, slice.byteOffset + slice.byteLength);
            stmts.push(
              db.prepare(
                `INSERT OR REPLACE INTO ${tableName} (key, data, size) VALUES (?, ?, ?)`,
              ).bind(chunkKey(k, i), buf, slice.length),
            );
          }
        }
      }

      await db.batch(stmts);
    },

    async delete(path) {
      await ensureTable();
      const k = key(path);
      await db.prepare(
        `DELETE FROM ${tableName} WHERE key = ? OR key LIKE ?`,
      ).bind(k, `${k}::chunk::%`).run();
    },

    async exists(path) {
      await ensureTable();
      const k = key(path);
      const row = await db.prepare(
        `SELECT 1 FROM ${tableName} WHERE key = ? LIMIT 1`,
      ).bind(k).first();
      return row !== null;
    },

    async list(prefix) {
      await ensureTable();
      const fullPrefix = keyPrefix + (prefix ?? "");
      const result = await db.prepare(
        `SELECT key FROM ${tableName} WHERE key LIKE ? AND key NOT LIKE '%::chunk::%'`,
      ).bind(`${fullPrefix}%`).all<{ key: string }>();

      return result.results.map((r) => r.key.slice(keyPrefix.length));
    },
  };
}
