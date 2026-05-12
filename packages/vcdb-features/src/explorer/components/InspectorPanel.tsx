import { useState, useEffect, useCallback } from "react";
import { Button, Input, VectorInput, FormField } from "@vcdb/ui-kit";
import { useDatabase } from "../../context/DatabaseContext";
import { useToast } from "@vcdb/ui-kit/toast";
import { useAsyncFn } from "react-use";
import styles from "./InspectorPanel.module.css";

type Attrs = Record<string, string | number | boolean | null>;

type DataRow = {
  id: number;
  score?: number;
  attrs: Record<string, unknown> | null;
  vector?: number[];
};

type InspectorPanelProps = {
  row: DataRow | null;
  onUpdate?: () => void;
  onDelete?: () => void;
  className?: string;
};

export function InspectorPanel({ row, onUpdate, onDelete, className }: InspectorPanelProps) {
  const { getById, updateAttrs, upsert, deleteById } = useDatabase();
  const toast = useToast();

  const [editedAttrs, setEditedAttrs] = useState<Record<string, string>>({});
  const [vector, setVector] = useState<number[]>([]);
  const [hasChanges, setHasChanges] = useState(false);

  useEffect(() => {
    if (!row) {
      setEditedAttrs({});
      setVector([]);
      setHasChanges(false);
      return;
    }

    const attrs: Record<string, string> = {};
    if (row.attrs) {
      for (const [key, value] of Object.entries(row.attrs)) {
        attrs[key] = typeof value === "string" ? value : JSON.stringify(value);
      }
    }
    setEditedAttrs(attrs);
    setHasChanges(false);

    if (row.vector) {
      setVector(row.vector);
    } else {
      getById(row.id)
        .then((data) => {
          if (data) {
            setVector(data.vector);
          }
        })
        .catch(() => {});
    }
  }, [row, getById]);

  const handleAttrChange = useCallback((key: string, value: string) => {
    setEditedAttrs((prev) => ({ ...prev, [key]: value }));
    setHasChanges(true);
  }, []);

  const handleVectorChange = useCallback((newVector: number[]) => {
    setVector(newVector);
    setHasChanges(true);
  }, []);

  const [saveState, handleSave] = useAsyncFn(async () => {
    if (!row) {
      return;
    }

    try {
      const attrs: Attrs = {};
      for (const [key, value] of Object.entries(editedAttrs)) {
        try {
          const parsed = JSON.parse(value);
          if (
            typeof parsed === "string" ||
            typeof parsed === "number" ||
            typeof parsed === "boolean" ||
            parsed === null
          ) {
            attrs[key] = parsed;
          } else {
            attrs[key] = value;
          }
        } catch {
          attrs[key] = value;
        }
      }

      if (vector.length > 0 && row.vector && vector.join(",") !== row.vector.join(",")) {
        await upsert(row.id, { vector, attrs });
      } else {
        await updateAttrs(row.id, attrs);
      }

      toast.success("Saved successfully");
      setHasChanges(false);
      onUpdate?.();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Save failed");
    }
  }, [row, editedAttrs, vector, upsert, updateAttrs, toast, onUpdate]);

  const [deleteState, handleDelete] = useAsyncFn(async () => {
    if (!row) {
      return;
    }

    try {
      await deleteById(row.id);
      toast.success("Deleted successfully");
      onDelete?.();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Delete failed");
    }
  }, [row, deleteById, toast, onDelete]);

  const classNames = [styles.panel, className].filter(Boolean).join(" ");

  if (!row) {
    return (
      <div className={classNames}>
        <div className={styles.empty}>
          <p>Select a row to inspect</p>
        </div>
      </div>
    );
  }

  return (
    <div className={classNames}>
      <div className={styles.header}>
        <h3 className={styles.title}>Inspector</h3>
        {hasChanges && <span className={styles.unsaved}>Unsaved</span>}
      </div>

      <div className={styles.content}>
        <FormField label="ID">
          <span className={styles.idValue}>{row.id}</span>
        </FormField>

        {row.score !== undefined && (
          <FormField label="Score">
            <span className={styles.scoreValue}>{row.score.toFixed(4)}</span>
          </FormField>
        )}

        <FormField label="Vector" description={`${vector.length} dimensions`}>
          <VectorInput value={vector} onChange={handleVectorChange} previewCount={3} />
        </FormField>

        <FormField label="Attributes">
          <div className={styles.attrs}>
            {Object.entries(editedAttrs).map(([key, value]) => (
              <div key={key} className={styles.attrRow}>
                <span className={styles.attrKey}>{key}</span>
                <Input
                  value={value}
                  onChange={(e) => handleAttrChange(key, e.target.value)}
                  className={styles.attrInput}
                />
              </div>
            ))}
            {Object.keys(editedAttrs).length === 0 && (
              <span className={styles.noAttrs}>No attributes</span>
            )}
          </div>
        </FormField>
      </div>

      <div className={styles.actions}>
        <Button
          size="sm"
          variant="primary"
          onClick={handleSave}
          loading={saveState.loading}
          disabled={!hasChanges}
        >
          Save
        </Button>
        <Button
          size="sm"
          variant="danger"
          onClick={handleDelete}
          loading={deleteState.loading}
        >
          Delete
        </Button>
      </div>
    </div>
  );
}
