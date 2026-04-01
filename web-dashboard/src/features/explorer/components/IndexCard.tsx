import { Button, StatusBadge } from "@/components/ui";
import type { IndexEntry } from "@/contexts/DatabaseContext";
import styles from "./IndexCard.module.css";

type IndexCardProps = {
  entry: IndexEntry;
  onEdit: () => void;
  onRebuild: () => void;
  onDelete: () => void;
  rebuilding?: boolean;
};

function getIndexTypeLabel(entry: IndexEntry): string {
  const { def } = entry;
  switch (def.kind) {
    case "hnsw":
      return "HNSW";
    case "ivf":
      return "IVF";
    case "bruteforce":
      return "Bruteforce";
    case "combined":
      return `${getVectorLabel(def.vector.kind)} + ${getAttrLabel(def.attribute.kind)}`;
    case "bptree":
    case "lsm":
    case "bitmap":
    case "basic":
      return getAttrLabel(def.kind);
    default:
      return "Unknown";
  }
}

function getVectorLabel(kind: string): string {
  switch (kind) {
    case "hnsw":
      return "HNSW";
    case "ivf":
      return "IVF";
    case "bruteforce":
      return "Bruteforce";
    default:
      return kind;
  }
}

function getAttrLabel(kind: string): string {
  switch (kind) {
    case "bptree":
      return "B+Tree";
    case "lsm":
      return "LSM";
    case "bitmap":
      return "Bitmap";
    case "basic":
      return "Basic";
    default:
      return kind;
  }
}

export function IndexCard({ entry, onEdit, onRebuild, onDelete, rebuilding }: IndexCardProps) {
  const typeLabel = getIndexTypeLabel(entry);
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
