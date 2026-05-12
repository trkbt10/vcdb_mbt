import { forwardRef, type SelectHTMLAttributes } from "react";
import styles from "./Select.module.css";

export type SelectOption = {
  readonly value: string;
  readonly label: string;
  readonly disabled?: boolean;
};

type SelectVariant = "default" | "minimal";

type SelectProps = Omit<SelectHTMLAttributes<HTMLSelectElement>, "children"> & {
  options: ReadonlyArray<SelectOption>;
  placeholder?: string;
  variant?: SelectVariant;
};

export const Select = forwardRef<HTMLSelectElement, SelectProps>(function Select(
  { options, placeholder, variant = "default", className, ...props },
  ref,
) {
  const wrapperClass = [
    styles.wrapper,
    styles[variant],
    className,
  ].filter(Boolean).join(" ");

  return (
    <div className={wrapperClass}>
      <select
        ref={ref}
        className={styles.select}
        {...props}
      >
        {placeholder && (
          <option value="" disabled>
            {placeholder}
          </option>
        )}
        {options.map((opt) => (
          <option key={opt.value} value={opt.value} disabled={opt.disabled}>
            {opt.label}
          </option>
        ))}
      </select>
      <span className={styles.chevron}>
        <svg
          width="12"
          height="12"
          viewBox="0 0 12 12"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
        >
          <path d="M3 4.5l3 3 3-3" />
        </svg>
      </span>
    </div>
  );
});
