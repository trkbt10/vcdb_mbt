import { useState, useMemo } from "react";
import styles from "./VectorInput.module.css";

type VectorInputProps = {
  value: number[];
  onChange?: (value: number[]) => void;
  readonly?: boolean;
  previewCount?: number;
  className?: string;
};

function formatNumber(n: number): string {
  if (Number.isInteger(n)) {
    return n.toString();
  }
  return n.toFixed(4).replace(/\.?0+$/, "");
}

export function VectorInput({
  value,
  onChange,
  readonly = false,
  previewCount = 4,
  className,
}: VectorInputProps) {
  const [expanded, setExpanded] = useState(false);
  const [editText, setEditText] = useState("");
  const [editing, setEditing] = useState(false);

  const preview = useMemo(() => {
    if (value.length <= previewCount) {
      return `[${value.map(formatNumber).join(", ")}]`;
    }
    const shown = value.slice(0, previewCount).map(formatNumber).join(", ");
    return `[${shown}, ... (${value.length})]`;
  }, [value, previewCount]);

  const fullText = useMemo(() => {
    return value.map(formatNumber).join(", ");
  }, [value]);

  const handleStartEdit = () => {
    if (readonly || !onChange) {
      return;
    }
    setEditText(fullText);
    setEditing(true);
  };

  const handleSave = () => {
    if (!onChange) {
      return;
    }
    const parsed = editText
      .split(",")
      .map((s) => s.trim())
      .filter((s) => s !== "")
      .map(Number);

    if (parsed.some(Number.isNaN)) {
      return;
    }

    onChange(parsed);
    setEditing(false);
  };

  const handleCancel = () => {
    setEditing(false);
    setEditText("");
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSave();
    } else if (e.key === "Escape") {
      handleCancel();
    }
  };

  const classNames = [styles.container, className].filter(Boolean).join(" ");

  if (editing) {
    return (
      <div className={classNames}>
        <textarea
          className={styles.textarea}
          value={editText}
          onChange={(e) => setEditText(e.target.value)}
          onKeyDown={handleKeyDown}
          onBlur={handleSave}
          autoFocus
          rows={4}
        />
        <div className={styles.editActions}>
          <button className={styles.actionBtn} onClick={handleSave}>
            Save
          </button>
          <button className={styles.actionBtn} onClick={handleCancel}>
            Cancel
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className={classNames}>
      <div className={styles.preview} onClick={expanded ? undefined : () => setExpanded(true)}>
        {expanded ? (
          <div className={styles.expanded}>
            <code className={styles.fullVector}>[{fullText}]</code>
            <button className={styles.collapseBtn} onClick={() => setExpanded(false)}>
              Collapse
            </button>
          </div>
        ) : (
          <code className={styles.previewText}>{preview}</code>
        )}
      </div>
      {!readonly && onChange && !expanded && (
        <button className={styles.editBtn} onClick={handleStartEdit}>
          Edit
        </button>
      )}
    </div>
  );
}
