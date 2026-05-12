export type Metric = "Cosine" | "L2" | "Dot";
export type Strategy = "Bruteforce" | "HNSW" | "IVF";

export type DatabaseStats = {
  size: number;
  dim: number;
  metric: Metric;
  strategy: Strategy;
};

export type DatabaseInfo = {
  id: string;
  name: string;
  /** Optional gateway host. Populated when the registry tracks remote connections. */
  host?: string;
  /** Optional gateway port. Populated when the registry tracks remote connections. */
  port?: number;
  stats?: DatabaseStats;
};

/** Embedding generation strategy applied to records as they're ingested. */
export type EmbeddingStrategy = "none" | "hash" | "openai" | "custom";

export type DatabaseEmbeddingConfig =
  | { readonly strategy: "none" }
  | { readonly strategy: "hash" }
  | {
      readonly strategy: "openai";
      readonly config: {
        readonly provider: "openai";
        readonly apiKeyEnv?: string;
        readonly model?: string;
        readonly baseURL?: string;
      };
    }
  | {
      readonly strategy: "custom";
      readonly config: {
        readonly provider: "custom";
        readonly endpointURL: string;
      };
    };
