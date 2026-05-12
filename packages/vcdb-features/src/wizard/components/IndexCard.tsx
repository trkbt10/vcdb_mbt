import type { IndexEntry } from "../types";
import {
  getIndexCategory,
  getIndexDescription,
  getIndexIcon,
} from "../../index-editor";
import styles from "./IndexCard.module.css";

type IndexCardProps = {
  entry: IndexEntry;
  onEdit: () => void;
  onDelete: () => void;
  canDelete: boolean;
};

export function IndexCard({ entry, onEdit, onDelete, canDelete }: IndexCardProps) {
  const { name, config } = entry;

  return (
    <div className={styles.indexCard}>
      <div className={styles.indexIcon}>{getIndexIcon(config.kind)}</div>

      <div className={styles.indexContent}>
        <div className={styles.indexHeader}>
          <span className={styles.indexName}>{name}</span>
          <span className={styles.indexKind}>
            {getIndexCategory(config.kind).toLowerCase()}
          </span>
        </div>
        <p className={styles.indexDescription}>{getIndexDescription(config)}</p>
      </div>

      <div className={styles.indexActions}>
        <button
          type="button"
          className={styles.iconButton}
          onClick={onEdit}
          title="Edit index"
        >
          <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2">
            <path d="M11.5 2.5l2 2M2 14l1-4 9-9 2 2-9 9-4 1z" />
          </svg>
        </button>
        <button
          type="button"
          className={styles.iconButton}
          data-variant="delete"
          onClick={onDelete}
          disabled={!canDelete}
          title={canDelete ? "Delete index" : "Cannot delete the only index"}
        >
          <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2">
            <path d="M2 4h12M5 4V2h6v2M6 7v5M10 7v5M3 4l1 10h8l1-10" />
          </svg>
        </button>
      </div>
    </div>
  );
}
