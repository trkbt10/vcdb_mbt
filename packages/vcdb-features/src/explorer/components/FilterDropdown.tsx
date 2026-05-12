import { useState, useRef, useEffect, useCallback } from "react";
import { FilterEditor, getActiveFilters, type FilterCondition } from "./FilterEditor";
import styles from "./FilterDropdown.module.css";

type FilterDropdownProps = {
  filters: FilterCondition[];
  onChange: (filters: FilterCondition[]) => void;
  className?: string;
};

export function FilterDropdown({ filters, onChange, className }: FilterDropdownProps) {
  const [isOpen, setIsOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  const activeCount = getActiveFilters(filters).length;
  const hasFilters = filters.length > 0;

  const handleClickOutside = useCallback((e: MouseEvent) => {
    if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
      setIsOpen(false);
    }
  }, []);

  const handleKeyDown = useCallback((e: KeyboardEvent) => {
    if (e.key === "Escape") {
      setIsOpen(false);
    }
  }, []);

  useEffect(() => {
    if (isOpen) {
      document.addEventListener("mousedown", handleClickOutside);
      document.addEventListener("keydown", handleKeyDown);
    }
    return () => {
      document.removeEventListener("mousedown", handleClickOutside);
      document.removeEventListener("keydown", handleKeyDown);
    };
  }, [isOpen, handleClickOutside, handleKeyDown]);

  const handleClear = () => {
    onChange([]);
  };

  const classNames = [styles.container, className].filter(Boolean).join(" ");

  return (
    <div ref={containerRef} className={classNames}>
      <button
        type="button"
        className={styles.trigger}
        data-active={activeCount > 0}
        data-open={isOpen}
        onClick={() => setIsOpen(!isOpen)}
        aria-expanded={isOpen}
        aria-haspopup="true"
      >
        <span className={styles.triggerIcon}>
          <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5">
            <path d="M2 4h12M4 8h8M6 12h4" strokeLinecap="round" />
          </svg>
        </span>
        <span>Filters</span>
        {activeCount > 0 && <span className={styles.badge}>{activeCount}</span>}
        <span className={styles.chevron}>
          <svg viewBox="0 0 10 10" fill="none" stroke="currentColor" strokeWidth="1.5">
            <path d="M2 3.5l3 3 3-3" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </span>
      </button>

      {isOpen && (
        <div className={styles.panel}>
          <div className={styles.panelHeader}>
            <span className={styles.panelTitle}>Filter Conditions</span>
            {hasFilters && (
              <button type="button" className={styles.clearBtn} onClick={handleClear}>
                Clear all
              </button>
            )}
          </div>
          <div className={styles.panelContent}>
            <FilterEditor filters={filters} onChange={onChange} />
          </div>
        </div>
      )}
    </div>
  );
}
