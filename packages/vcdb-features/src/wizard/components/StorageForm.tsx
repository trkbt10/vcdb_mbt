import { Input, Button } from "@vcdb/ui-kit";
import type { WizardData } from "../types";
import { WizardStepLayout } from "./WizardStepLayout";
import styles from "./StorageForm.module.css";

type StorageFormProps = {
  data: WizardData;
  onUpdate: (data: Partial<WizardData>) => void;
  onNext: () => void;
  onPrev: () => void;
};

export function StorageForm({
  data,
  onUpdate,
  onNext,
  onPrev,
}: StorageFormProps) {
  return (
    <WizardStepLayout
      title="Storage Configuration"
      description="Configure storage URIs for index and vector data."
      actions={(
        <>
          <Button variant="ghost" onClick={onPrev}>
            Back
          </Button>
          <Button variant="primary" onClick={onNext}>
            Continue
          </Button>
        </>
      )}
    >
      <div className={styles.fields}>
        <div className={styles.fieldGroup}>
          <Input
            label="Index URI"
            value={data.storage.index}
            onChange={(e) =>
              onUpdate({
                storage: { ...data.storage, index: e.target.value },
              })
            }
            placeholder="file://./data/index"
          />
          <p className={styles.hint}>
            URI for index files (manifests, HNSW graph, etc.)
          </p>
        </div>

        <div className={styles.fieldGroup}>
          <Input
            label="Data URI"
            value={data.storage.data}
            onChange={(e) =>
              onUpdate({
                storage: { ...data.storage, data: e.target.value },
              })
            }
            placeholder="file://./data/vectors"
          />
          <p className={styles.hint}>
            URI for vector data segments
          </p>
        </div>

        <div className={styles.separator} />

        <h4 className={styles.sectionTitle}>Server Connection</h4>

        <div className={styles.row}>
          <div className={styles.fieldGroup}>
            <Input
              label="Host"
              value={data.server.host}
              onChange={(e) =>
                onUpdate({
                  server: { ...data.server, host: e.target.value },
                })
              }
              placeholder="localhost"
            />
          </div>

          <div className={styles.fieldGroup}>
            <Input
              label="Port"
              type="number"
              value={String(data.server.port)}
              onChange={(e) =>
                onUpdate({
                  server: { ...data.server, port: Number(e.target.value) },
                })
              }
              placeholder="3000"
            />
          </div>
        </div>
        <p className={styles.hint}>
          The host and port where the database server will run
        </p>
      </div>
    </WizardStepLayout>
  );
}
