import { Button } from "@vcdb/ui-kit";
import { getIndexCategory, getIndexSummary } from "../../index-editor";
import type { WizardData } from "../types";
import { WizardStepLayout } from "./WizardStepLayout";
import styles from "./ReviewStep.module.css";

type ReviewStepProps = {
  data: WizardData;
  onPrev: () => void;
  onSubmit: () => void;
  loading?: boolean;
};

export function ReviewStep({
  data,
  onPrev,
  onSubmit,
  loading,
}: ReviewStepProps) {
  // WizardData already mirrors AppConfig structure
  const outputConfig = {
    name: data.name,
    database: data.database,
    indexes: data.indexes,
    storage: data.storage,
    server: data.server,
  };

  const indexEntries = Object.entries(data.indexes);

  return (
    <WizardStepLayout
      title="Review Configuration"
      description="Review your configuration before creating the database."
      actions={(
        <>
          <Button variant="ghost" onClick={onPrev}>
            Back
          </Button>
          <Button variant="primary" onClick={onSubmit} loading={loading}>
            Create Database
          </Button>
        </>
      )}
    >
      <div className={styles.review}>
        <section className={styles.reviewSection}>
          <h3 className={styles.reviewTitle}>Database</h3>
          <dl className={styles.reviewList}>
            <div className={styles.reviewItem}>
              <dt>Name</dt>
              <dd>{data.name}</dd>
            </div>
            <div className={styles.reviewItem}>
              <dt>Dimensions</dt>
              <dd>{data.database.dim}</dd>
            </div>
            <div className={styles.reviewItem}>
              <dt>Metric</dt>
              <dd>{data.database.metric}</dd>
            </div>
          </dl>
        </section>

        <section className={styles.reviewSection}>
          <h3 className={styles.reviewTitle}>Indexes ({indexEntries.length})</h3>
          <div className={styles.reviewGroup}>
            {indexEntries.map(([name, config]) => (
              <dl key={name} className={styles.reviewList}>
                <div className={styles.reviewItem}>
                  <dt>Name</dt>
                  <dd>{name}</dd>
                </div>
                <div className={styles.reviewItem}>
                  <dt>Type</dt>
                  <dd>{getIndexCategory(config.kind)}</dd>
                </div>
                <div className={styles.reviewItem}>
                  <dt>Config</dt>
                  <dd>{getIndexSummary(config)}</dd>
                </div>
              </dl>
            ))}
          </div>
        </section>

        <section className={styles.reviewSection}>
          <h3 className={styles.reviewTitle}>Storage</h3>
          <dl className={styles.reviewList}>
            <div className={styles.reviewItem}>
              <dt>Index URI</dt>
              <dd className={styles.mono}>{data.storage.index}</dd>
            </div>
            <div className={styles.reviewItem}>
              <dt>Data URI</dt>
              <dd className={styles.mono}>{data.storage.data}</dd>
            </div>
          </dl>
        </section>

        <section className={styles.reviewSection}>
          <h3 className={styles.reviewTitle}>Server Connection</h3>
          <dl className={styles.reviewList}>
            <div className={styles.reviewItem}>
              <dt>Host</dt>
              <dd className={styles.mono}>{data.server.host}</dd>
            </div>
            <div className={styles.reviewItem}>
              <dt>Port</dt>
              <dd className={styles.mono}>{data.server.port}</dd>
            </div>
          </dl>
        </section>
      </div>

      <div className={styles.configPreview}>
        <h4 className={styles.previewTitle}>Configuration Preview</h4>
        <pre className={styles.previewCode}>
          {JSON.stringify(outputConfig, null, 2)}
        </pre>
      </div>
    </WizardStepLayout>
  );
}
