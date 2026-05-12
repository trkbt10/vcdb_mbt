import { useState, useEffect } from "react";
import { useAsync } from "react-use";
import { Button, Spinner, Section } from "@vcdb/ui-kit";
import { useDatabase } from "../../context/DatabaseContext";
import { useToast } from "@vcdb/ui-kit/toast";
import {
  StorageEditor,
  CrushEditor,
  DEFAULT_CRUSH_CONFIG,
  type StorageConfig,
  type CrushConfig,
} from "../../storage-editor";
import styles from "./StorageTab.module.css";

export function StorageTab() {
  const { getDbConfig, stats } = useDatabase();
  const toast = useToast();

  const [storage, setStorage] = useState<StorageConfig>({ index: "", data: "" });
  const [crush, setCrush] = useState<CrushConfig>(DEFAULT_CRUSH_CONFIG);
  const [hasChanges, setHasChanges] = useState(false);

  // Fetch current database config
  const configState = useAsync(async () => {
    const config = await getDbConfig();
    return config;
  }, [getDbConfig]);

  // Initialize state from fetched config
  useEffect(() => {
    if (configState.value) {
      const cfg = configState.value;

      // Parse storage config (storage can be string, object, or resolver functions)
      if (cfg.storage) {
        const storageObj = cfg.storage;
        if (typeof storageObj === "string") {
          setStorage({ index: storageObj, data: storageObj });
        } else if (typeof storageObj === "object") {
          // Extract string URIs if available, otherwise use empty strings
          const indexUri = typeof storageObj.index === "string" ? storageObj.index : "";
          const dataUri = typeof storageObj.data === "string" ? storageObj.data : "";
          setStorage({ index: indexUri, data: dataUri });
        }
      }

      // Parse CRUSH config from index options
      if (cfg.index) {
        setCrush({
          pgs: cfg.index.pgs ?? DEFAULT_CRUSH_CONFIG.pgs,
          shards: cfg.index.shards ?? DEFAULT_CRUSH_CONFIG.shards,
          replicas: cfg.index.replicas ?? DEFAULT_CRUSH_CONFIG.replicas,
          segmented: cfg.index.segmented ?? DEFAULT_CRUSH_CONFIG.segmented,
          segmentBytes: cfg.index.segmentBytes ?? DEFAULT_CRUSH_CONFIG.segmentBytes,
        });
      }
    }
  }, [configState.value]);

  const handleStorageChange = (newStorage: StorageConfig) => {
    setStorage(newStorage);
    setHasChanges(true);
  };

  const handleCrushChange = (newCrush: CrushConfig) => {
    setCrush(newCrush);
    setHasChanges(true);
  };

  const handleSave = () => {
    // Note: Saving config changes typically requires server restart
    // For now, we'll just show a message
    toast.info("Configuration changes require server restart to take effect.");
    setHasChanges(false);
  };

  if (configState.loading) {
    return (
      <div className={styles.loading}>
        <Spinner />
        <span>Loading configuration...</span>
      </div>
    );
  }

  if (configState.error) {
    return (
      <div className={styles.error}>
        <p>Failed to load configuration</p>
        <p className={styles.errorDetail}>{configState.error.message}</p>
      </div>
    );
  }

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <h3 className={styles.title}>Storage Configuration</h3>
        <Button
          onClick={handleSave}
          disabled={!hasChanges}
          variant={hasChanges ? "primary" : "secondary"}
        >
          Save Changes
        </Button>
      </div>

      <div className={styles.content}>
        <StorageEditor
          config={storage}
          onChange={handleStorageChange}
        />

        <CrushEditor
          config={crush}
          onChange={handleCrushChange}
        />

        {stats && (
          <Section title="Segment Statistics" description="Current storage usage">
            <div className={styles.statsGrid}>
              <div className={styles.statItem}>
                <span className={styles.statLabel}>Total Vectors</span>
                <span className={styles.statValue}>{stats.size.toLocaleString()}</span>
              </div>
              <div className={styles.statItem}>
                <span className={styles.statLabel}>Dimensions</span>
                <span className={styles.statValue}>{stats.dim}</span>
              </div>
              <div className={styles.statItem}>
                <span className={styles.statLabel}>Metric</span>
                <span className={styles.statValue}>{stats.metric}</span>
              </div>
              <div className={styles.statItem}>
                <span className={styles.statLabel}>Strategy</span>
                <span className={styles.statValue}>{stats.strategy}</span>
              </div>
            </div>
          </Section>
        )}
      </div>

      {hasChanges && (
        <div className={styles.notice}>
          <span>You have unsaved changes.</span>
          <span className={styles.noticeHint}>
            Note: Storage configuration changes require server restart.
          </span>
        </div>
      )}
    </div>
  );
}
