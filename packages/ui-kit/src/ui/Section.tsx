import type { ReactNode } from "react";
import styles from "./Section.module.css";

type SectionProps = {
  title: string;
  description?: string;
  children: ReactNode;
  className?: string;
};

export function Section({ title, description, children, className }: SectionProps) {
  return (
    <section className={`${styles.section} ${className ?? ""}`}>
      <div className={styles.header}>
        <h4 className={styles.title}>{title}</h4>
        {description && <p className={styles.description}>{description}</p>}
      </div>
      <div className={styles.content}>{children}</div>
    </section>
  );
}
