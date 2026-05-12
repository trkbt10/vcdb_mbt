import type { ReactNode } from "react";
import styles from "./FormField.module.css";

type FormFieldProps = {
  label?: string;
  description?: string;
  error?: string;
  required?: boolean;
  children: ReactNode;
};

export function FormField({
  label,
  description,
  error,
  required,
  children,
}: FormFieldProps) {
  return (
    <div className={styles.field} data-error={Boolean(error)}>
      {label && (
        <label className={styles.label}>
          {label}
          {required && <span className={styles.required}>*</span>}
        </label>
      )}
      {description && <p className={styles.description}>{description}</p>}
      <div className={styles.control}>{children}</div>
      {error && <span className={styles.error}>{error}</span>}
    </div>
  );
}
