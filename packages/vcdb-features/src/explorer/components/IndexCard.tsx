import { Button, StatusBadge } from "@vcdb/ui-kit";
import type { IndexEntry } from "../../context/DatabaseContext";
import { getIndexTypeLabel } from "../../index-editor";
import styles from "./IndexCard.module.css";

type IndexCardProps = {
  entry: IndexEntry;
  onEdit: () => void;
  onRebuild: () => void;
  onDelete: () => void;
  rebuilding?: boolean;
};

export function IndexCard({ entry, onEdit, onRebuild, onDelete, rebuilding }: IndexCardProps) {
  const typeLabel = getIndexTypeLabel(entry.def);
  const isCombined = entry.def.kind === "combined";

  return (
    <div className={styles.card} data-status={entry.status}>
      <div className={styles.header}>
        <h4 className={styles.name}>{entry.name}</h4>
        <StatusBadge status={entry.status} showLabel />
      </div>

      <div className={styles.info}>
        <div className={styles.type}>
          <span className={styles.label}>Type:</span>
          <span className={styles.value}>{typeLabel}</span>
        </div>
        {isCombined && (
          <div className={styles.execution}>
            <span className={styles.label}>Execution:</span>
            <span className={styles.value}>
              {(entry.def as { execution?: string }).execution ?? "auto"}
            </span>
          </div>
        )}
      </div>

      {entry.status === "error" && entry.errorMessage && (
        <div className={styles.error}>
          <span className={styles.errorLabel}>Error:</span>
          <span className={styles.errorMessage}>{entry.errorMessage}</span>
        </div>
      )}

      <div className={styles.actions}>
        <Button size="sm" variant="ghost" onClick={onEdit}>
          Edit
        </Button>
        <Button
          size="sm"
          variant="ghost"
          onClick={onRebuild}
          loading={rebuilding}
          disabled={entry.status === "building"}
        >
          Rebuild
        </Button>
        <Button size="sm" variant="ghost" onClick={onDelete}>
          Delete
        </Button>
      </div>
    </div>
  );
}
