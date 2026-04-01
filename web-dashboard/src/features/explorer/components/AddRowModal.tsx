import { useState } from "react";
import { Modal, Button, Input, VectorInput } from "@/components/ui";
import { useDatabase } from "@/contexts/DatabaseContext";
import { useToast } from "@/contexts/ToastContext";
import { useAsyncFn } from "react-use";
import styles from "./AddRowModal.module.css";

type Attrs = Record<string, string | number | boolean | null>;

type AddRowModalProps = {
  isOpen: boolean;
  onClose: () => void;
  onSuccess?: () => void;
};

type AttrEntry = {
  key: string;
  value: string;
};

export function AddRowModal({ isOpen, onClose, onSuccess }: AddRowModalProps) {
  const { upsert, stats } = useDatabase();
  const toast = useToast();

  const [id, setId] = useState("");
  const [vector, setVector] = useState<number[]>([]);
  const [attrs, setAttrs] = useState<AttrEntry[]>([]);

  const handleVectorChange = (newVector: number[]) => {
    setVector(newVector);
  };

  const handleAddAttr = () => {
    setAttrs([...attrs, { key: "", value: "" }]);
  };

  const handleRemoveAttr = (index: number) => {
    setAttrs(attrs.filter((_, i) => i !== index));
  };

  const handleAttrChange = (index: number, field: "key" | "value", value: string) => {
    setAttrs(
      attrs.map((attr, i) => {
        if (i !== index) {
          return attr;
        }
        return { ...attr, [field]: value };
      }),
    );
  };

  const [saveState, handleSave] = useAsyncFn(async () => {
    const parsedId = parseInt(id, 10);
    if (Number.isNaN(parsedId)) {
      toast.error("Invalid ID");
      return;
    }

    if (vector.length === 0) {
      toast.error("Vector is required");
      return;
    }

    if (stats && vector.length !== stats.dim) {
      toast.error(`Vector must have ${stats.dim} dimensions`);
      return;
    }

    const parsedAttrs: Attrs = {};
    for (const { key, value } of attrs) {
      if (key.trim() === "") {
        continue;
      }
      try {
        const parsed = JSON.parse(value);
        if (
          typeof parsed === "string" ||
          typeof parsed === "number" ||
          typeof parsed === "boolean" ||
          parsed === null
        ) {
          parsedAttrs[key] = parsed;
        } else {
          parsedAttrs[key] = value;
        }
      } catch {
        parsedAttrs[key] = value;
      }
    }

    try {
      await upsert(parsedId, { vector, attrs: parsedAttrs });
      toast.success("Row added successfully");
      onSuccess?.();
      handleClose();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to add row");
    }
  }, [id, vector, attrs, stats, upsert, toast, onSuccess]);

  const handleClose = () => {
    setId("");
    setVector([]);
    setAttrs([]);
    onClose();
  };

  const handleGenerateEmptyVector = () => {
    if (stats) {
      setVector(new Array(stats.dim).fill(0));
    }
  };

  const footer = (
    <div className={styles.footer}>
      <Button variant="ghost" onClick={handleClose}>
        Cancel
      </Button>
      <Button variant="primary" onClick={handleSave} loading={saveState.loading}>
        Add Row
      </Button>
    </div>
  );

  return (
    <Modal open={isOpen} onClose={handleClose} title="Add New Row" footer={footer}>
      <div className={styles.content}>
        <div className={styles.field}>
          <label className={styles.label}>ID</label>
          <Input
            data-testid="add-row-id"
            type="number"
            placeholder="Enter unique ID..."
            value={id}
            onChange={(e) => setId(e.target.value)}
          />
        </div>

        <div className={styles.field}>
          <label className={styles.label}>
            Vector
            {stats && <span className={styles.hint}>({stats.dim} dimensions)</span>}
          </label>
          {vector.length === 0 ? (
            <div className={styles.vectorEmpty}>
              <Button size="sm" variant="ghost" onClick={handleGenerateEmptyVector} data-testid="add-row-init-vector">
                Initialize {stats?.dim ?? 0}-dim vector
              </Button>
            </div>
          ) : (
            <VectorInput value={vector} onChange={handleVectorChange} previewCount={4} />
          )}
        </div>

        <div className={styles.field}>
          <label className={styles.label}>Attributes</label>
          <div className={styles.attrList}>
            {attrs.map((attr, index) => (
              <div key={index} className={styles.attrRow}>
                <Input
                  placeholder="key"
                  value={attr.key}
                  onChange={(e) => handleAttrChange(index, "key", e.target.value)}
                  className={styles.attrKey}
                />
                <Input
                  placeholder="value"
                  value={attr.value}
                  onChange={(e) => handleAttrChange(index, "value", e.target.value)}
                  className={styles.attrValue}
                />
                <Button
                  size="sm"
                  variant="ghost"
                  className={styles.removeBtn}
                  onClick={() => handleRemoveAttr(index)}
                >
                  ×
                </Button>
              </div>
            ))}
            <Button size="sm" variant="ghost" onClick={handleAddAttr}>
              + Add Attribute
            </Button>
          </div>
        </div>
      </div>
    </Modal>
  );
}
