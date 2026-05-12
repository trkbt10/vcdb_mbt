import { Database, StatusBadge, Trash, Settings } from "@vcdb/ui-kit";
import type { DatabaseInfo } from "../types";
import styles from "./ConnectionItem.module.css";

type ConnectionItemProps = {
  database: DatabaseInfo;
  mode: "compact" | "full";
  selected: boolean;
  onSelect: () => void;
  onRemove: () => void;
  onEmbeddingConfig?: () => void;
};

export function ConnectionItem({
  database,
  mode,
  selected,
  onSelect,
  onRemove,
  onEmbeddingConfig,
}: ConnectionItemProps) {
  const status = "online";
  const handleRemove = (e: React.MouseEvent) => {
    e.stopPropagation();
    onRemove();
  };

  const handleEmbeddingConfig = (e: React.MouseEvent) => {
    e.stopPropagation();
    onEmbeddingConfig?.();
  };

  const statusTitle = "online";

  if (mode === "compact") {
    return (
      <div
        className={styles.compact}
        data-selected={selected}
        data-status={status}
        data-testid={`collection-item-${database.name}`}
        data-collection-name={database.name}
        onClick={onSelect}
        role="button"
        tabIndex={0}
        onKeyDown={(e) => e.key === "Enter" && onSelect()}
      >
        <span className={styles.icon}>
          <Database size={16} />
        </span>
        <span className={styles.content}>
          <span className={styles.name}>{database.name}</span>
          <span className={styles.host}>gateway collection</span>
        </span>
        <StatusBadge status={status} size="sm" title={statusTitle} />
        {onEmbeddingConfig && (
          <button
            className={styles.settingsButton}
            onClick={handleEmbeddingConfig}
            title="Embedding Config"
          >
            <Settings size={14} />
          </button>
        )}
        <button
          className={styles.removeButton}
          onClick={handleRemove}
          title="Remove"
        >
          <Trash size={14} />
        </button>
      </div>
    );
  }

  return (
    <div className={styles.full} data-selected={selected} data-status={status}>
      <div className={styles.fullHeader}>
        <div className={styles.fullTitle}>
          <h3>{database.name}</h3>
          <StatusBadge status={status} showLabel title={statusTitle} />
        </div>
        <p className={styles.fullHost}>gateway collection</p>
      </div>

      {database.stats && (
        <div className={styles.stats}>
          <div className={styles.stat}>
            <span className={styles.statLabel}>Vectors</span>
            <span className={styles.statValue}>
              {database.stats.size.toLocaleString()}
            </span>
          </div>
          <div className={styles.stat}>
            <span className={styles.statLabel}>Dimensions</span>
            <span className={styles.statValue}>{database.stats.dim}</span>
          </div>
          <div className={styles.stat}>
            <span className={styles.statLabel}>Metric</span>
            <span className={styles.statValue}>{database.stats.metric}</span>
          </div>
        </div>
      )}

      <div className={styles.fullActions}>
        <button className={styles.primaryButton} onClick={onSelect}>
          Open
        </button>
        {onEmbeddingConfig && (
          <button className={styles.secondaryButton} onClick={handleEmbeddingConfig}>
            Embedding
          </button>
        )}
        <button className={styles.secondaryButton} onClick={onRemove}>
          Remove
        </button>
      </div>
    </div>
  );
}
