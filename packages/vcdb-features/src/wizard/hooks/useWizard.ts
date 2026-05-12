import { useState, useCallback, useMemo } from "react";
import type {
  CombinedIndexConfig,
  IndexConfig,
} from "vcdb/meta/index-types";
import {
  createDefaultAttrIndex,
  createDefaultVectorIndex,
} from "../../index-editor";
import type { WizardData } from "../types";

// Re-export factories so the wizard's own consumers keep their existing
// import surface even though the SoT lives in @vcdb/vcdb-features/index-editor.
export { createDefaultAttrIndex, createDefaultVectorIndex };
export { createDefaultField } from "../../index-editor";

// =============================================================================
// Wizard Step Types
// =============================================================================

export type WizardStep = "database" | "index" | "storage" | "review";

const STEPS: WizardStep[] = ["database", "index", "storage", "review"];

const STEP_LABELS: Record<WizardStep, string> = {
  database: "Database",
  index: "Index",
  storage: "Storage",
  review: "Review",
};

// =============================================================================
// Default Config Factories
// =============================================================================

/**
 * Combined index factory is wizard-specific (no consumer in index-editor),
 * so it stays here and composes the shared factories.
 */
export function createDefaultCombinedIndex(): CombinedIndexConfig {
  return {
    kind: "combined",
    vector: createDefaultVectorIndex(),
    attribute: createDefaultAttrIndex(),
    execution: "auto",
  };
}

// =============================================================================
// Default Wizard Data (mirrors AppConfig structure)
// =============================================================================

const DEFAULT_DATA: WizardData = {
  name: "my-database",
  storage: {
    index: "file://./data/index",
    data: "file://./data/vectors",
  },
  database: {
    dim: 384,
    metric: "cosine",
  },
  indexes: {
    primary: createDefaultVectorIndex(),
  },
  server: {
    host: "localhost",
    port: 3000,
  },
};

// =============================================================================
// useWizard Hook
// =============================================================================

export function useWizard() {
  const [currentStep, setCurrentStep] = useState<WizardStep>("database");
  const [data, setData] = useState<WizardData>(DEFAULT_DATA);

  const currentIndex = STEPS.indexOf(currentStep);
  const isFirst = currentIndex === 0;
  const isLast = currentIndex === STEPS.length - 1;

  const next = useCallback(() => {
    if (!isLast) {
      setCurrentStep(STEPS[currentIndex + 1]);
    }
  }, [currentIndex, isLast]);

  const prev = useCallback(() => {
    if (!isFirst) {
      setCurrentStep(STEPS[currentIndex - 1]);
    }
  }, [currentIndex, isFirst]);

  const goTo = useCallback((step: WizardStep) => {
    setCurrentStep(step);
  }, []);

  const updateData = useCallback((partial: Partial<WizardData>) => {
    setData((prev) => ({ ...prev, ...partial }));
  }, []);

  const updateDatabase = useCallback((partial: Partial<WizardData["database"]>) => {
    setData((prev) => ({
      ...prev,
      database: { ...prev.database, ...partial },
    }));
  }, []);

  // Index management: Record<string, IndexConfig>
  const setIndex = useCallback((name: string, config: IndexConfig) => {
    setData((prev) => ({
      ...prev,
      indexes: { ...prev.indexes, [name]: config },
    }));
  }, []);

  const removeIndex = useCallback((name: string) => {
    setData((prev) => {
      const { [name]: removed, ...rest } = prev.indexes;
      void removed; // Used for destructuring removal
      return { ...prev, indexes: rest };
    });
  }, []);

  const renameIndex = useCallback((oldName: string, newName: string) => {
    setData((prev) => {
      const { [oldName]: config, ...rest } = prev.indexes;
      if (!config) {
        return prev;
      }
      return { ...prev, indexes: { ...rest, [newName]: config } };
    });
  }, []);

  const reset = useCallback(() => {
    setCurrentStep("database");
    setData(DEFAULT_DATA);
  }, []);

  const steps = useMemo(() => {
    return STEPS.map((step) => ({
      id: step,
      label: STEP_LABELS[step],
      completed: STEPS.indexOf(step) < currentIndex,
      current: step === currentStep,
    }));
  }, [currentIndex, currentStep]);

  return {
    currentStep,
    data,
    steps,
    isFirst,
    isLast,
    next,
    prev,
    goTo,
    updateData,
    updateDatabase,
    setIndex,
    removeIndex,
    renameIndex,
    reset,
  };
}
