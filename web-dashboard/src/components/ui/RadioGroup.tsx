import styles from "./RadioGroup.module.css";

type RadioOption<T extends string> = {
  value: T;
  label: string;
  description?: string;
};

type RadioGroupProps<T extends string> = {
  name: string;
  value: T;
  options: RadioOption<T>[];
  onChange: (value: T) => void;
  orientation?: "horizontal" | "vertical";
};

export function RadioGroup<T extends string>({
  name,
  value,
  options,
  onChange,
  orientation = "vertical",
}: RadioGroupProps<T>) {
  return (
    <div
      className={styles.group}
      data-orientation={orientation}
      role="radiogroup"
    >
      {options.map((option) => (
        <label
          key={option.value}
          className={styles.option}
          data-selected={value === option.value}
        >
          <input
            type="radio"
            name={name}
            value={option.value}
            checked={value === option.value}
            onChange={() => onChange(option.value)}
            className={styles.input}
          />
          <span className={styles.radio} />
          <span className={styles.content}>
            <span className={styles.label}>{option.label}</span>
            {option.description && (
              <span className={styles.description}>{option.description}</span>
            )}
          </span>
        </label>
      ))}
    </div>
  );
}
