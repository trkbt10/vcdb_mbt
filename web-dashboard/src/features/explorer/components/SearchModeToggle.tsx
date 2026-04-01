import styles from "./SearchModeToggle.module.css";

export type SearchMode = "text" | "vector";

type SearchModeToggleProps = {
  mode: SearchMode;
  onChange: (mode: SearchMode) => void;
  textEnabled?: boolean;
  className?: string;
};

export function SearchModeToggle({ mode, onChange, textEnabled = false, className }: SearchModeToggleProps) {
  const classNames = [styles.container, className].filter(Boolean).join(" ");

  return (
    <div className={classNames}>
      <div className={styles.indicator} data-active={mode} />
      <button
        type="button"
        className={styles.option}
        data-active={mode === "text"}
        data-disabled={!textEnabled}
        onClick={() => textEnabled && onChange("text")}
        disabled={!textEnabled}
        aria-pressed={mode === "text"}
        title={textEnabled ? undefined : "Requires embedding configuration"}
      >
        <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5">
          <path d="M3 4h10M3 8h7M3 12h9" strokeLinecap="round" />
        </svg>
        Text
      </button>
      <button
        type="button"
        className={styles.option}
        data-active={mode === "vector"}
        onClick={() => onChange("vector")}
        aria-pressed={mode === "vector"}
      >
        <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5">
          <circle cx="4" cy="8" r="2" />
          <circle cx="12" cy="4" r="2" />
          <circle cx="12" cy="12" r="2" />
          <path d="M6 8l4-3M6 8l4 3" />
        </svg>
        Vector
      </button>
    </div>
  );
}
