import type {
  Attrs,
  BulkResult,
  CollectionInfo,
  CollectionStats,
  ListVectorsResult,
  PointRecord,
  SearchHit,
  VectorRowInput,
} from "./types";

type GatewayEnvelope<T> = {
  status: "ok" | "error";
  result?: T;
  error?: string;
};

type GatewayPoint = {
  id: number;
  payload: Attrs;
  vector: number[];
};

type GatewaySearchPayload = {
  result: Array<{
    id: number;
    score: number;
    payload?: Attrs;
    vector?: number[];
  }>;
  time: number;
};

type GatewayScrollPayload = {
  points: Array<{
    id: number;
    payload?: Attrs;
    vector?: number[];
  }>;
  next_page_offset?: number;
};

type CreateCollectionInput = {
  name: string;
  config: {
    dim: number;
    metric?: string;
    strategy?: string;
  };
};

async function readPayload<T>(res: Response): Promise<T> {
  const data = (await res.json().catch(() => ({}))) as GatewayEnvelope<T> & Record<string, unknown>;
  if (!res.ok || data.status === "error") {
    throw new Error(data.error ?? `HTTP ${res.status}`);
  }
  if (data.status === "ok" && "result" in data) {
    return data.result as T;
  }
  return data as T;
}

function toStats(info: CollectionInfo): CollectionStats {
  return {
    size: info.vectors_count,
    dim: info.dim,
    metric: info.metric,
    strategy: info.strategy,
  };
}

export function createGatewayClient(apiBase = "") {
  const collectionPath = (name: string) => `${apiBase}/collections/${encodeURIComponent(name)}`;
  const healthPath = `${apiBase}/healthz`;

  return {
    async health(): Promise<{ ok: boolean }> {
      const res = await fetch(healthPath);
      if (!res.ok) {
        throw new Error(`Health check failed: ${res.statusText}`);
      }
      return { ok: true };
    },

    async listCollections(): Promise<CollectionInfo[]> {
      const res = await fetch(`${apiBase}/collections`);
      const data = await readPayload<{ collections?: CollectionInfo[] }>(res);
      return data.collections ?? [];
    },

    async createCollection(input: CreateCollectionInput): Promise<void> {
      const res = await fetch(collectionPath(input.name), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(input.config),
      });
      await readPayload(res);
    },

    async deleteCollection(name: string): Promise<void> {
      const res = await fetch(collectionPath(name), { method: "DELETE" });
      await readPayload(res);
    },

    async getCollection(name: string): Promise<CollectionInfo> {
      const res = await fetch(collectionPath(name));
      return readPayload<CollectionInfo>(res);
    },

    async getCollectionStats(name: string): Promise<CollectionStats> {
      return toStats(await this.getCollection(name));
    },

    async listVectors(name: string, options?: { limit?: number; offset?: number }): Promise<ListVectorsResult> {
      const limit = options?.limit ?? 100;
      const offset = options?.offset;
      const res = await fetch(`${collectionPath(name)}/points/scroll`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          limit,
          offset,
          with_payload: true,
          with_vector: false,
        }),
      });
      const payload = await readPayload<GatewayScrollPayload>(res);
      const stats = await this.getCollectionStats(name);
      return {
        rows: payload.points.map((point) => ({
          id: point.id,
          attrs: point.payload ?? null,
        })),
        total: stats.size,
        offset: offset ?? 0,
        limit,
      };
    },

    async search(name: string, vector: number[], options?: { k?: number }): Promise<SearchHit[]> {
      const res = await fetch(`${collectionPath(name)}/points/search`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          vector,
          limit: options?.k ?? 10,
          with_payload: true,
          with_vector: false,
        }),
      });
      const payload = await readPayload<GatewaySearchPayload>(res);
      return payload.result.map((hit) => ({
        id: hit.id,
        score: hit.score,
        attrs: hit.payload ?? null,
        vector: hit.vector,
      }));
    },

    async getPoint(name: string, id: number): Promise<PointRecord | null> {
      const res = await fetch(`${collectionPath(name)}/points/${id}`);
      if (res.status === 404) {
        return null;
      }
      const point = await readPayload<GatewayPoint>(res);
      return { id: point.id, vector: point.vector, attrs: point.payload ?? {} };
    },

    async upsertPoint(name: string, id: number, data: { vector: number[]; attrs?: Attrs }): Promise<void> {
      const res = await fetch(`${collectionPath(name)}/points`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          points: [{ id, vector: data.vector, payload: data.attrs ?? {} }],
        }),
      });
      await readPayload(res);
    },

    async bulkUpsert(name: string, rows: VectorRowInput[]): Promise<BulkResult> {
      const res = await fetch(`${collectionPath(name)}/points`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          points: rows.map((row) => ({
            id: row.id,
            vector: row.vector,
            payload: row.attrs ?? {},
          })),
        }),
      });
      await readPayload(res);
      return {
        ok: true,
        results: rows.map((row) => ({ id: row.id, ok: true })),
      };
    },

    async updateAttrs(name: string, id: number, attrs: Attrs): Promise<void> {
      const point = await this.getPoint(name, id);
      if (!point) {
        throw new Error(`Point ${id} not found`);
      }
      await this.upsertPoint(name, id, { vector: point.vector, attrs });
    },

    async deletePoint(name: string, id: number): Promise<void> {
      const res = await fetch(`${collectionPath(name)}/points/${id}`, { method: "DELETE" });
      await readPayload(res);
    },

  };
}
