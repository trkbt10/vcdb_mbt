import { Button, FormField, Input, Select } from "@vcdb/ui-kit";
import type { FieldDef } from "vcdb/types";
import { TYPE_OPTIONS, OP_OPTIONS } from "../constants";
import styles from "./FieldDefsEditor.module.css";

type FieldDefsEditorProps = {
  fields: FieldDef[];
  onChange: (fields: FieldDef[]) => void;
};

export function createDefaultField(): FieldDef {
  return { path: "", type: "string", ops: ["eq"] };
}

export function FieldDefsEditor({ fields, onChange }: FieldDefsEditorProps) {
  const handleAdd = () => {
    onChange([...fields, createDefaultField()]);
  };

  const handleRemove = (index: number) => {
    onChange(fields.filter((_, i) => i !== index));
  };

  const handleChange = (index: number, field: FieldDef) => {
    const updated = [...fields];
    updated[index] = field;
    onChange(updated);
  };

  const handleOpsToggle = (index: number, op: AttrOp) => {
    const field = fields[index];
    const hasOp = field.ops.includes(op);
    const newOps = hasOp ? field.ops.filter((o) => o !== op) : [...field.ops, op];
    // Ensure at least one op
    if (newOps.length === 0) {
      return;
    }
    handleChange(index, { ...field, ops: newOps });
  };

  return (
    <div className={styles.fieldsEditor}>
      <div className={styles.fieldsHeader}>
        <span className={styles.fieldsTitle}>Indexed Fields</span>
        <Button size="sm" variant="ghost" onClick={handleAdd}>
          + Add Field
        </Button>
      </div>

      {fields.length === 0 && (
        <p className={styles.emptyMessage}>No fields defined. Add at least one field to index.</p>
      )}

      {fields.map((field, index) => (
        <div key={index} className={styles.fieldRow}>
          <div className={styles.fieldInputs}>
            <FormField label="Path" description="e.g., category, user.id">
              <Input
                value={field.path}
                placeholder="field.path"
                onChange={(e) => handleChange(index, { ...field, path: e.target.value })}
              />
            </FormField>

            <FormField label="Type">
              <Select
                value={field.type ?? "string"}
                options={TYPE_OPTIONS}
                onChange={(e) =>
                  handleChange(index, {
                    ...field,
                    type: e.target.value as FieldDef["type"],
                  })
                }
              />
            </FormField>
          </div>

          <div className={styles.opsRow}>
            <span className={styles.opsLabel}>Operations:</span>
            {OP_OPTIONS.map((op) => (
              <label key={op.value} className={styles.opCheckbox}>
                <input
                  type="checkbox"
                  checked={field.ops.includes(op.value)}
                  onChange={() => handleOpsToggle(index, op.value)}
                />
                <span>{op.label}</span>
              </label>
            ))}
          </div>

          <Button
            size="sm"
            variant="ghost"
            className={styles.removeFieldBtn}
            onClick={() => handleRemove(index)}
            disabled={fields.length <= 1}
            title={fields.length <= 1 ? "At least one field required" : "Remove field"}
          >
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M2 4h12M5 4V2h6v2M6 7v5M10 7v5M3 4l1 10h8l1-10" />
            </svg>
          </Button>
        </div>
      ))}
    </div>
  );
}
