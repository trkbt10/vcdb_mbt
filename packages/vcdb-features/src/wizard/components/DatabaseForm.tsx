import { Input, Button, FormField, RadioGroup } from "@vcdb/ui-kit";
import type { Metric } from "vcdb/types/public";
import type { WizardData } from "../types";
import { WizardStepLayout } from "./WizardStepLayout";
import styles from "./DatabaseForm.module.css";

type DatabaseFormProps = {
  data: WizardData;
  onUpdateData: (data: Partial<WizardData>) => void;
  onUpdateDatabase: (data: Partial<WizardData["database"]>) => void;
  onNext: () => void;
};

const metricOptions = [
  { value: "cosine" as const, label: "Cosine Similarity" },
  { value: "l2" as const, label: "Euclidean (L2)" },
  { value: "dot" as const, label: "Dot Product" },
];

export function DatabaseForm({
  data,
  onUpdateData,
  onUpdateDatabase,
  onNext,
}: DatabaseFormProps) {
  return (
    <WizardStepLayout
      title="Database Configuration"
      description="Set the basic parameters for your vector database."
      actions={(
        <Button variant="primary" onClick={onNext}>
          Continue
        </Button>
      )}
    >
      <div className={styles.fields}>
        <Input
          label="Database Name"
          value={data.name}
          onChange={(e) => onUpdateData({ name: e.target.value })}
          placeholder="my-database"
        />

        <Input
          label="Dimensions"
          type="number"
          value={data.database.dim}
          onChange={(e) => onUpdateDatabase({ dim: parseInt(e.target.value) || 0 })}
          placeholder="384"
        />

        <FormField label="Distance Metric">
          <RadioGroup
            name="metric"
            value={data.database.metric ?? "cosine"}
            options={metricOptions}
            onChange={(metric) => onUpdateDatabase({ metric: metric as Metric })}
            orientation="horizontal"
          />
        </FormField>
      </div>
    </WizardStepLayout>
  );
}
