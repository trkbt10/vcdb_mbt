import { Input, Select } from "@vcdb/ui-kit";
import styles from "./FilterEditor.module.css";

export type FilterCondition = {
  key: string;
  operator: "=" | "!=" | ">" | "<" | ">=" | "<=";
  value: string;
};

type FilterEditorProps = {
  filters: FilterCondition[];
  onChange: (filters: FilterCondition[]) => void;
  className?: string;
};

const OPERATORS = [
  { value: "=", label: "=" },
  { value: "!=", label: "≠" },
  { value: ">", label: ">" },
  { value: "<", label: "<" },
  { value: ">=", label: "≥" },
  { value: "<=", label: "≤" },
];

export function FilterEditor({ filters, onChange, className }: FilterEditorProps) {
  const handleAdd = () => {
    onChange([...filters, { key: "", operator: "=", value: "" }]);
  };

  const handleRemove = (index: number) => {
    onChange(filters.filter((_, i) => i !== index));
  };

  const handleChange = (index: number, field: keyof FilterCondition, value: string) => {
    const updated = filters.map((f, i) => {
      if (i !== index) {
        return f;
      }
      return { ...f, [field]: value };
    });
    onChange(updated);
  };

  const classNames = [styles.container, className].filter(Boolean).join(" ");

  return (
    <div className={classNames}>
      <div className={styles.rows}>
        {filters.map((filter, index) => (
          <div key={index} className={styles.row}>
            <Input
              variant="minimal"
              className={styles.keyInput}
              placeholder="key"
              value={filter.key}
              onChange={(e) => handleChange(index, "key", e.target.value)}
            />
            <Select
              variant="minimal"
              className={styles.operatorSelect}
              value={filter.operator}
              onChange={(e) => handleChange(index, "operator", e.target.value as FilterCondition["operator"])}
              options={OPERATORS}
            />
            <Input
              variant="minimal"
              className={styles.valueInput}
              placeholder="value"
              value={filter.value}
              onChange={(e) => handleChange(index, "value", e.target.value)}
            />
            <button
              type="button"
              className={styles.removeBtn}
              onClick={() => handleRemove(index)}
              aria-label="Remove filter"
            >
              ×
            </button>
          </div>
        ))}
      </div>
      {filters.length === 0 && (
        <span className={styles.empty}>No filters</span>
      )}
      <button type="button" className={styles.addBtn} onClick={handleAdd}>
        + Add
      </button>
    </div>
  );
}

/**
 * Get active filters (filters with both key and value filled in)
 */
export function getActiveFilters(filters: FilterCondition[]): FilterCondition[] {
  return filters.filter((f) => f.key.trim() !== "" && f.value.trim() !== "");
}
