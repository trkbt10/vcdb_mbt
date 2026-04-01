import type { ReactNode } from "react";
import styles from "./WizardStepLayout.module.css";

type WizardStepLayoutProps = {
  title: string;
  description?: string;
  children: ReactNode;
  actions?: ReactNode;
};

export function WizardStepLayout({
  title,
  description,
  children,
  actions,
}: WizardStepLayoutProps) {
  return (
    <div className={styles.form}>
      <div className={styles.header}>
        <h2 className={styles.title}>{title}</h2>
        {description && <p className={styles.description}>{description}</p>}
      </div>
      {children}
      {actions ? <div className={styles.actions}>{actions}</div> : null}
    </div>
  );
}
