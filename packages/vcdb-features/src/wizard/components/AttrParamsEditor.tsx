import { FormField, Select } from "@vcdb/ui-kit";
import type { AttributeIndexConfig } from "vcdb/meta/index-types";
import type { FieldDef, CompositeOrder } from "vcdb/types";
import { ORDER_OPTIONS } from "../../constants";
import { FieldDefsEditor } from "./FieldDefsEditor";
import styles from "./AttrParamsEditor.module.css";

type AttrParamsEditorProps = {
  kind: AttributeIndexConfig["kind"];
  config: AttributeIndexConfig;
  onChange: (config: AttributeIndexConfig) => void;
};

export function AttrParamsEditor({ kind, config, onChange }: AttrParamsEditorProps) {
  // All attribute configs have fields
  const fields = getFields(config);

  const handleFieldsChange = (newFields: FieldDef[]) => {
    onChange({ ...config, fields: newFields } as AttributeIndexConfig);
  };

  return (
    <div className={styles.parameterFields}>
      <FieldDefsEditor fields={fields} onChange={handleFieldsChange} />

      {/* Order option for bptree/lsm */}
      {(kind === "bptree" || kind === "lsm") && (
        <FormField label="Key Order" description="How composite keys are ordered">
          <Select
            value={getOrder(config)}
            options={ORDER_OPTIONS}
            onChange={(e) =>
              onChange({ ...config, order: e.target.value as CompositeOrder } as AttributeIndexConfig)
            }
          />
        </FormField>
      )}
    </div>
  );
}

function getFields(config: AttributeIndexConfig): FieldDef[] {
  return config.fields ?? [];
}

function getOrder(config: AttributeIndexConfig): CompositeOrder {
  if (config.kind === "bptree" || config.kind === "lsm") {
    return config.order ?? "declared";
  }
  return "declared";
}
