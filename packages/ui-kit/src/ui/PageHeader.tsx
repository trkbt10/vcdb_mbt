import type { ReactNode } from "react";
import styles from "./PageHeader.module.css";

type PageHeaderProps = {
  title: string;
  subtitle?: string;
  backButton?: ReactNode;
  actions?: ReactNode;
};

export function PageHeader({
  title,
  subtitle,
  backButton,
  actions,
}: PageHeaderProps) {
  return (
    <header className={styles.header}>
      <div className={styles.content}>
        {backButton && <div className={styles.back}>{backButton}</div>}
        <h1 className={styles.title}>{title}</h1>
        {subtitle && <p className={styles.subtitle}>{subtitle}</p>}
      </div>
      {actions && <div className={styles.actions}>{actions}</div>}
    </header>
  );
}
