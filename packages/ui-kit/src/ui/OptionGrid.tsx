import type { ReactNode } from "react";
import styles from "./OptionGrid.module.css";

export type OptionGridItem<T extends string> = {
  value: T;
  label: string;
  description?: string;
  icon?: ReactNode;
};

type OptionGridProps<T extends string> = {
  options: OptionGridItem<T>[];
  value: T;
  onChange: (value: T) => void;
  columns?: number;
  className?: string;
};

export function OptionGrid<T extends string>({
  options,
  value,
  onChange,
  columns,
  className,
}: OptionGridProps<T>) {
  const gridStyle = columns
    ? { gridTemplateColumns: `repeat(${columns}, 1fr)` }
    : undefined;

  return (
    <div
      className={`${styles.grid} ${className ?? ""}`}
      style={gridStyle}
    >
      {options.map((option) => (
        <button
          key={option.value}
          type="button"
          className={styles.option}
          data-selected={value === option.value}
          onClick={() => onChange(option.value)}
        >
          {option.icon && <span className={styles.icon}>{option.icon}</span>}
          <span className={styles.label}>{option.label}</span>
          {option.description && (
            <span className={styles.description}>{option.description}</span>
          )}
        </button>
      ))}
    </div>
  );
}
