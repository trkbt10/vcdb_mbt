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
  stats?: DatabaseStats;
};
