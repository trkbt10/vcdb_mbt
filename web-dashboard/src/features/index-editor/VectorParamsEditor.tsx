import { FormField, Input, Select } from "@/components/ui";
import type { VectorIndexConfig } from "vcdb/meta/index-types";
import { HNSW_CONSTRAINTS, IVF_CONSTRAINTS } from "vcdb/types/public";
import { METRIC_OPTIONS } from "@/constants";
import styles from "./VectorParamsEditor.module.css";

type VectorParamsEditorProps = {
  kind: VectorIndexConfig["kind"];
  config: VectorIndexConfig;
  onChange: (config: VectorIndexConfig) => void;
};

export function VectorParamsEditor({ kind, config, onChange }: VectorParamsEditorProps) {
  switch (kind) {
    case "hnsw":
      return <HNSWParams config={config as VectorIndexConfig & { kind: "hnsw" }} onChange={onChange} />;
    case "ivf":
      return <IVFParams config={config as VectorIndexConfig & { kind: "ivf" }} onChange={onChange} />;
    case "bruteforce":
      return <BruteforceParams config={config as VectorIndexConfig & { kind: "bruteforce" }} onChange={onChange} />;
  }
}

function HNSWParams({
  config,
  onChange,
}: {
  config: VectorIndexConfig & { kind: "hnsw" };
  onChange: (c: VectorIndexConfig) => void;
}) {
  return (
    <div className={styles.parameterFields}>
      <div className={styles.parameterRow}>
        <FormField label="Metric" description="Distance function">
          <Select
            value={config.metric ?? "cosine"}
            options={METRIC_OPTIONS}
            onChange={(e) => onChange({ ...config, metric: e.target.value as "cosine" | "l2" | "dot" })}
          />
        </FormField>
        <FormField
          label="M"
          description={`Max connections (${HNSW_CONSTRAINTS.M.min}-${HNSW_CONSTRAINTS.M.max})`}
        >
          <Input
            type="number"
            value={config.M ?? 16}
            min={HNSW_CONSTRAINTS.M.min}
            max={HNSW_CONSTRAINTS.M.max}
            onChange={(e) => onChange({ ...config, M: parseInt(e.target.value, 10) })}
          />
        </FormField>
      </div>
      <div className={styles.parameterRow}>
        <FormField
          label="efConstruction"
          description={`Build quality (${HNSW_CONSTRAINTS.efConstruction.min}-${HNSW_CONSTRAINTS.efConstruction.max})`}
        >
          <Input
            type="number"
            value={config.efConstruction ?? 200}
            min={HNSW_CONSTRAINTS.efConstruction.min}
            max={HNSW_CONSTRAINTS.efConstruction.max}
            onChange={(e) => onChange({ ...config, efConstruction: parseInt(e.target.value, 10) })}
          />
        </FormField>
        <FormField label="efSearch" description="Search quality">
          <Input
            type="number"
            value={config.efSearch ?? 50}
            min={1}
            onChange={(e) => onChange({ ...config, efSearch: parseInt(e.target.value, 10) })}
          />
        </FormField>
      </div>
    </div>
  );
}

function IVFParams({
  config,
  onChange,
}: {
  config: VectorIndexConfig & { kind: "ivf" };
  onChange: (c: VectorIndexConfig) => void;
}) {
  return (
    <div className={styles.parameterFields}>
      <div className={styles.parameterRow}>
        <FormField label="Metric" description="Distance function">
          <Select
            value={config.metric ?? "cosine"}
            options={METRIC_OPTIONS}
            onChange={(e) => onChange({ ...config, metric: e.target.value as "cosine" | "l2" | "dot" })}
          />
        </FormField>
        <FormField
          label="nlist"
          description={`Number of clusters (${IVF_CONSTRAINTS.nlist.min}-${IVF_CONSTRAINTS.nlist.max})`}
        >
          <Input
            type="number"
            value={config.nlist ?? 64}
            min={IVF_CONSTRAINTS.nlist.min}
            max={IVF_CONSTRAINTS.nlist.max}
            onChange={(e) => onChange({ ...config, nlist: parseInt(e.target.value, 10) })}
          />
        </FormField>
      </div>
      <div className={styles.parameterRow}>
        <FormField label="nprobe" description="Clusters to search">
          <Input
            type="number"
            value={config.nprobe ?? 8}
            min={1}
            onChange={(e) => onChange({ ...config, nprobe: parseInt(e.target.value, 10) })}
          />
        </FormField>
      </div>
    </div>
  );
}

function BruteforceParams({
  config,
  onChange,
}: {
  config: VectorIndexConfig & { kind: "bruteforce" };
  onChange: (c: VectorIndexConfig) => void;
}) {
  return (
    <div className={styles.parameterFields}>
      <div className={styles.parameterRow}>
        <FormField label="Metric" description="Distance function">
          <Select
            value={config.metric ?? "cosine"}
            options={METRIC_OPTIONS}
            onChange={(e) => onChange({ ...config, metric: e.target.value as "cosine" | "l2" | "dot" })}
          />
        </FormField>
      </div>
    </div>
  );
}
