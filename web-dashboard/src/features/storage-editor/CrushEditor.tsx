import { FormField, Input, Section, Toggle } from "@/components/ui";
import styles from "./CrushEditor.module.css";

export type CrushConfig = {
  pgs: number;
  shards: number;
  replicas: number;
  segmented: boolean;
  segmentBytes: number;
};

export const DEFAULT_CRUSH_CONFIG: CrushConfig = {
  pgs: 64,
  shards: 1,
  replicas: 1,
  segmented: true,
  segmentBytes: 1024 * 1024, // 1MB
};

type CrushEditorProps = {
  config: CrushConfig;
  onChange: (config: CrushConfig) => void;
  readonly?: boolean;
};

export function CrushEditor({ config, onChange, readonly = false }: CrushEditorProps) {
  const segmentMB = Math.round(config.segmentBytes / (1024 * 1024));

  return (
    <Section
      title="CRUSH Configuration"
      description="Configure data placement and distribution strategy"
    >
      <div className={styles.fields}>
        <div className={styles.row}>
          <FormField
            label="Placement Groups"
            description="Data distribution units"
          >
            <Input
              type="number"
              value={config.pgs}
              onChange={(e) => onChange({ ...config, pgs: parseInt(e.target.value, 10) || 64 })}
              min={1}
              max={1024}
              disabled={readonly}
            />
          </FormField>

          <FormField
            label="Shards"
            description="Storage targets"
          >
            <Input
              type="number"
              value={config.shards}
              onChange={(e) => onChange({ ...config, shards: parseInt(e.target.value, 10) || 1 })}
              min={1}
              max={64}
              disabled={readonly}
            />
          </FormField>

          <FormField
            label="Replicas"
            description="Copies per placement group"
          >
            <Input
              type="number"
              value={config.replicas}
              onChange={(e) => onChange({ ...config, replicas: parseInt(e.target.value, 10) || 1 })}
              min={1}
              max={16}
              disabled={readonly}
            />
          </FormField>
        </div>

        <div className={styles.advancedSection}>
          <h5 className={styles.advancedTitle}>Advanced</h5>

          <div className={styles.advancedFields}>
            <Toggle
              checked={config.segmented}
              onChange={(checked) => onChange({ ...config, segmented: checked })}
              label="Segmented Storage"
              description="Split data into multiple segment files"
              disabled={readonly}
            />

            {config.segmented && (
              <FormField
                label="Segment Size (MB)"
                description="Maximum size per segment file"
              >
                <Input
                  type="number"
                  value={segmentMB}
                  onChange={(e) =>
                    onChange({
                      ...config,
                      segmentBytes: (parseInt(e.target.value, 10) || 1) * 1024 * 1024,
                    })
                  }
                  min={1}
                  max={1024}
                  disabled={readonly}
                />
              </FormField>
            )}
          </div>
        </div>
      </div>
    </Section>
  );
}
