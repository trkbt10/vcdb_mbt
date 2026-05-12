import { useState, useCallback, useRef, useImperativeHandle, forwardRef } from "react";
import { Input, Button } from "@vcdb/ui-kit";
import styles from "./SearchBar.module.css";

type SearchMode = "vector" | "filter";

const PLACEHOLDERS: Record<SearchMode, string> = {
  filter: 'Filter: key=value or {"must": [...]}',
  vector: "Vector: 0.1, 0.2, 0.3, ...",
};

type SearchBarProps = {
  onSearch: (query: string, mode: SearchMode) => void;
  onClear: () => void;
  loading?: boolean;
};

export type SearchBarRef = {
  focus: () => void;
};

export const SearchBar = forwardRef<SearchBarRef, SearchBarProps>(
  function SearchBar({ onSearch, onClear, loading }, ref) {
    const inputRef = useRef<HTMLInputElement>(null);
    const [mode, setMode] = useState<SearchMode>("filter");
    const [query, setQuery] = useState("");

    useImperativeHandle(ref, () => ({
      focus: () => {
        inputRef.current?.focus();
      },
    }));

  const handleSubmit = useCallback(
    (e: React.FormEvent) => {
      e.preventDefault();
      if (query.trim()) {
        onSearch(query.trim(), mode);
      }
    },
    [query, mode, onSearch],
  );

  const handleClear = useCallback(() => {
    setQuery("");
    onClear();
  }, [onClear]);

  return (
    <form className={styles.container} onSubmit={handleSubmit}>
      <div className={styles.modeToggle}>
        <button
          type="button"
          className={styles.modeBtn}
          data-active={mode === "filter"}
          onClick={() => setMode("filter")}
        >
          Filter
        </button>
        <button
          type="button"
          className={styles.modeBtn}
          data-active={mode === "vector"}
          onClick={() => setMode("vector")}
        >
          Vector
        </button>
      </div>

      <div className={styles.inputWrapper}>
        <Input
          ref={inputRef}
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder={PLACEHOLDERS[mode]}
          icon={
            <svg
              width="16"
              height="16"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
            >
              <circle cx="11" cy="11" r="8" />
              <line x1="21" y1="21" x2="16.65" y2="16.65" />
            </svg>
          }
        />
      </div>

      <div className={styles.actions}>
        <Button type="submit" variant="primary" loading={loading}>
          Search
        </Button>
        <Button type="button" variant="ghost" onClick={handleClear}>
          Clear
        </Button>
      </div>
    </form>
  );
  },
);
