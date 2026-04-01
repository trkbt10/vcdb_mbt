import { FormField, Input, Section } from "@/components/ui";
import styles from "./StorageEditor.module.css";

export type StorageConfig = {
  index: string;
  data: string;
};

type StorageEditorProps = {
  config: StorageConfig;
  onChange: (config: StorageConfig) => void;
  readonly?: boolean;
};

export function StorageEditor({ config, onChange, readonly = false }: StorageEditorProps) {
  return (
    <Section title="Storage URIs" description="Configure storage locations for index and vector data">
      <div className={styles.fields}>
        <FormField
          label="Index URI"
          description="URI for index files (manifests, HNSW graph, etc.)"
        >
          <Input
            value={config.index}
            onChange={(e) => onChange({ ...config, index: e.target.value })}
            placeholder="file://./data/index"
            disabled={readonly}
          />
        </FormField>

        <FormField
          label="Data URI"
          description="URI for vector data segments"
        >
          <Input
            value={config.data}
            onChange={(e) => onChange({ ...config, data: e.target.value })}
            placeholder="file://./data/vectors"
            disabled={readonly}
          />
        </FormField>

        <p className={styles.hint}>
          Supported schemes: <code>file://</code>, <code>memory://</code>
        </p>
      </div>
    </Section>
  );
}
