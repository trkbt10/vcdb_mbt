import { useState, forwardRef, useImperativeHandle, useRef, useMemo } from "react";
import { FilterDropdown } from "./FilterDropdown";
import type { FilterCondition } from "./FilterEditor";
import styles from "./QueryBar.module.css";

export type QueryBarRef = {
  focus: () => void;
};

export type SearchQuery = { type: "vector"; vector: number[] };

type QueryBarProps = {
  onSearch: (query: SearchQuery) => void;
  onFilterChange: (filters: FilterCondition[]) => void;
  filters: FilterCondition[];
  loading?: boolean;
  className?: string;
};

function parseVector(input: string): number[] | null {
  const cleaned = input.replace(/[\[\]]/g, "").trim();
  if (!cleaned) {
    return null;
  }

  const parts = cleaned.split(",").map((s) => s.trim()).filter(Boolean);
  const numbers = parts.map(Number);

  if (numbers.some(Number.isNaN)) {
    return null;
  }

  return numbers;
}

function formatVectorPreview(vector: number[], maxShow = 3): string {
  if (vector.length <= maxShow) {
    return `[${vector.map((n) => n.toFixed(2)).join(", ")}]`;
  }
  const shown = vector.slice(0, maxShow).map((n) => n.toFixed(2)).join(", ");
  return `[${shown}, ...(${vector.length})]`;
}

export const QueryBar = forwardRef<QueryBarRef, QueryBarProps>(function QueryBar(
  { onSearch, onFilterChange, filters, loading, className },
  ref,
) {
  const [inputValue, setInputValue] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);

  useImperativeHandle(ref, () => ({
    focus: () => inputRef.current?.focus(),
  }));

  // Parse vector from input when in vector mode
  const parsedVector = useMemo(() => parseVector(inputValue), [inputValue]);

  const canSearch = parsedVector !== null && parsedVector.length > 0;

  const handleSearch = () => {
    if (!canSearch || loading) {
      return;
    }

    if (parsedVector) {
      onSearch({ type: "vector", vector: parsedVector });
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSearch();
    }
  };

  const handleClearVector = () => {
    setInputValue("");
    inputRef.current?.focus();
  };

  const placeholder = "Enter vector: 0.1, 0.2, 0.3, ...";

  const classNames = [styles.container, className].filter(Boolean).join(" ");

  return (
    <div className={classNames}>
      <div className={styles.inputWrapper}>
        <input
          ref={inputRef}
          type="text"
          className={styles.input}
          data-testid="search-input"
          data-mode="vector"
          placeholder={placeholder}
          value={inputValue}
          onChange={(e) => setInputValue(e.target.value)}
          onKeyDown={handleKeyDown}
        />
      </div>

      {parsedVector && parsedVector.length > 0 && (
        <div className={styles.vectorPreview}>
          <code>{formatVectorPreview(parsedVector)}</code>
          <button type="button" onClick={handleClearVector} aria-label="Clear vector">
            ×
          </button>
        </div>
      )}

      <button
        type="button"
        className={styles.searchBtn}
        data-testid="search-submit"
        onClick={handleSearch}
        disabled={!canSearch || loading}
        data-loading={loading}
        aria-label="Search"
      >
        {loading ? (
          <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2">
            <circle cx="8" cy="8" r="6" strokeDasharray="28" strokeDashoffset="8" />
          </svg>
        ) : (
          <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5">
            <circle cx="7" cy="7" r="4" />
            <path d="M10 10l3.5 3.5" strokeLinecap="round" />
          </svg>
        )}
      </button>

      <div className={styles.divider} />

      <FilterDropdown filters={filters} onChange={onFilterChange} />

      <span className={styles.hint}>⌘K</span>
    </div>
  );
});
