import { useState } from "react";
import { useToast } from "@/contexts/ToastContext";
import { useRegistry } from "@/features/registry/hooks/useRegistry";
import { useWizard } from "./hooks/useWizard";
import {
  StepIndicator,
  DatabaseForm,
  IndexesForm,
  StorageForm,
  ReviewStep,
} from "./components";
import styles from "./WizardPage.module.css";

type WizardPageProps = {
  onClose: () => void;
};

export function WizardPage({ onClose }: WizardPageProps) {
  const { showToast } = useToast();
  const { createDatabase } = useRegistry();
  const [isSubmitting, setIsSubmitting] = useState(false);

  const {
    currentStep,
    data,
    steps,
    next,
    prev,
    updateData,
    updateDatabase,
    setIndex,
    removeIndex,
    renameIndex,
  } = useWizard();

  const handleSubmit = async () => {
    setIsSubmitting(true);
    try {
      await createDatabase({
        name: data.name,
        config: {
          dim: data.database.dim,
          metric: data.database.metric,
          strategy: data.database.strategy,
        },
      });
      showToast("Database created successfully", "success");
      onClose();
    } catch (err) {
      showToast(err instanceof Error ? err.message : "Failed to create database", "error");
    } finally {
      setIsSubmitting(false);
    }
  };

  const renderStep = () => {
    switch (currentStep) {
      case "database":
        return (
          <DatabaseForm
            data={data}
            onUpdateData={updateData}
            onUpdateDatabase={updateDatabase}
            onNext={next}
          />
        );
      case "index":
        return (
          <IndexesForm
            data={data}
            onSetIndex={setIndex}
            onRemoveIndex={removeIndex}
            onRenameIndex={renameIndex}
            onNext={next}
            onPrev={prev}
          />
        );
      case "storage":
        return (
          <StorageForm
            data={data}
            onUpdate={updateData}
            onNext={next}
            onPrev={prev}
          />
        );
      case "review":
        return (
          <ReviewStep
            data={data}
            onPrev={prev}
            onSubmit={handleSubmit}
            loading={isSubmitting}
          />
        );
      default:
        return null;
    }
  };

  return (
    <div className={styles.page}>
      <div className={styles.header}>
        <h1>Configuration Wizard</h1>
        <p className={styles.subtitle}>
          Create and configure a new vector database
        </p>
      </div>

      <div className={styles.content}>
        <StepIndicator steps={steps} />
        <div className={styles.stepContent}>{renderStep()}</div>
      </div>
    </div>
  );
}
