import { forwardRef, type InputHTMLAttributes, type ReactNode } from "react";
import styles from "./Input.module.css";

type InputVariant = "default" | "minimal";

type InputProps = InputHTMLAttributes<HTMLInputElement> & {
  label?: string;
  error?: string;
  icon?: ReactNode;
  variant?: InputVariant;
};

export const Input = forwardRef<HTMLInputElement, InputProps>(function Input(
  { label, error, icon, variant = "default", className, ...props },
  ref,
) {
  const wrapperClass = [
    styles.wrapper,
    styles[variant],
    className,
  ].filter(Boolean).join(" ");

  return (
    <div className={wrapperClass} data-error={Boolean(error)}>
      {label && <label className={styles.label}>{label}</label>}
      <div className={styles.inputWrapper}>
        {icon && <span className={styles.icon}>{icon}</span>}
        <input
          ref={ref}
          className={styles.input}
          data-has-icon={Boolean(icon)}
          {...props}
        />
      </div>
      {error && <span className={styles.error}>{error}</span>}
    </div>
  );
});
