import React from "react";
import styles from "./StepIndicator.module.css";

type Step = {
  id: string;
  label: string;
  completed: boolean;
  current: boolean;
};

type StepIndicatorProps = {
  steps: Step[];
  onStepClick?: (id: string) => void;
};

const CheckmarkIcon = (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3">
    <polyline points="20 6 9 17 4 12" />
  </svg>
);

function StepNumber({ completed, index }: { completed: boolean; index: number }): React.ReactNode {
  if (completed) {
    return CheckmarkIcon;
  }
  return index + 1;
}

export function StepIndicator({ steps, onStepClick }: StepIndicatorProps) {
  return (
    <div className={styles.container}>
      {steps.map((step, index) => (
        <div key={step.id} className={styles.stepWrapper}>
          <button
            className={styles.step}
            data-completed={step.completed}
            data-current={step.current}
            onClick={() => onStepClick?.(step.id)}
            disabled={!step.completed && !step.current}
          >
            <span className={styles.number}>
              <StepNumber completed={step.completed} index={index} />
            </span>
            <span className={styles.label}>{step.label}</span>
          </button>
          {index < steps.length - 1 && <div className={styles.connector} />}
        </div>
      ))}
    </div>
  );
}
