import React, { useMemo, useState, useCallback } from "react";
import {
  VECTOR_FIELD,
  type DataRecord,
  type FieldValue,
  type RecordId,
  type ScoredRecord,
} from "@vcdb/data-source";
import styles from "./DataTable.module.css";

export type Column = {
  key: string;
  label: string;
  width?: number;
  render?: (value: FieldValue | undefined, record: ScoredRecord) => React.ReactNode;
};

export type DataTableProps = {
  records: ScoredRecord[];
  columns?: Column[];
  selectedId?: RecordId | null;
  onSelect?: (record: ScoredRecord) => void;
  onDoubleClick?: (record: ScoredRecord) => void;
  pageSize?: number;
  loading?: boolean;
};

const ID_KEY = "__id";
const SCORE_KEY = "__score";

function renderCellValue(col: Column, value: FieldValue | undefined, record: ScoredRecord): React.ReactNode {
  if (col.render) {
    return col.render(value, record);
  }
  return formatValue(value);
}

type TableBodyContentProps = {
  loading: boolean;
  pagedRecords: ScoredRecord[];
  columns: Column[];
  selectedId?: RecordId | null;
  onSelect?: (record: ScoredRecord) => void;
  onDoubleClick?: (record: ScoredRecord) => void;
  getValue: (record: ScoredRecord, key: string) => FieldValue | undefined;
};

function TableBodyContent({
  loading,
  pagedRecords,
  columns,
  selectedId,
  onSelect,
  onDoubleClick,
  getValue,
}: TableBodyContentProps): React.ReactNode {
  if (loading) {
    return (
      <tr>
        <td colSpan={columns.length} className={styles.loading}>
          Loading...
        </td>
      </tr>
    );
  }
  if (pagedRecords.length === 0) {
    return (
      <tr>
        <td colSpan={columns.length} className={styles.empty}>
          No data
        </td>
      </tr>
    );
  }
  return pagedRecords.map((record, i) => (
    <tr
      key={String(record.id)}
      className={styles.tr}
      data-row-id={String(record.id)}
      data-odd={i % 2 === 1}
      data-selected={selectedId === record.id}
      onClick={() => onSelect?.(record)}
      onDoubleClick={() => onDoubleClick?.(record)}
    >
      {columns.map((col) => (
        <td key={col.key} className={styles.td}>
          {renderCellValue(col, getValue(record, col.key), record)}
        </td>
      ))}
    </tr>
  ));
}

function truncateVector(vector: FieldValue | undefined): string {
  if (!Array.isArray(vector) || vector.length === 0 || !vector.every((v) => typeof v === "number")) {
    return "[]";
  }
  const nums = vector as number[];
  const preview = nums.slice(0, 4).map((v) => v.toFixed(3));
  if (nums.length > 4) {
    return `[${preview.join(", ")}, ...]`;
  }
  return `[${preview.join(", ")}]`;
}

function formatValue(value: FieldValue | undefined): string {
  if (value === null || value === undefined) {
    return "-";
  }
  if (typeof value === "object") {
    return JSON.stringify(value);
  }
  return String(value);
}

function compareValues(a: FieldValue | undefined, b: FieldValue | undefined): number {
  if (a === b) return 0;
  if (a === null || a === undefined) return 1;
  if (b === null || b === undefined) return -1;
  if (typeof a === "number" && typeof b === "number") return a < b ? -1 : 1;
  return String(a) < String(b) ? -1 : 1;
}

export function DataTable({
  records,
  columns: propColumns,
  selectedId,
  onSelect,
  onDoubleClick,
  pageSize = 50,
  loading = false,
}: DataTableProps) {
  const [page, setPage] = useState(0);
  const [sortKey, setSortKey] = useState<string | null>(null);
  const [sortDir, setSortDir] = useState<"asc" | "desc">("asc");

  const hasScores = useMemo(() => records.some((r) => r.score !== undefined), [records]);
  const hasVector = useMemo(
    () => records.some((r) => Array.isArray(r.fields[VECTOR_FIELD])),
    [records],
  );

  const columns = useMemo<Column[]>(() => {
    if (propColumns) {
      return propColumns;
    }

    const baseColumns: Column[] = [{ key: ID_KEY, label: "ID", width: 80 }];
    if (hasScores) {
      baseColumns.push({ key: SCORE_KEY, label: "Score", width: 100 });
    }

    const fieldKeys = new Set<string>();
    for (const record of records) {
      for (const key of Object.keys(record.fields)) {
        if (key !== VECTOR_FIELD) {
          fieldKeys.add(key);
        }
      }
    }

    for (const key of fieldKeys) {
      baseColumns.push({ key, label: key });
    }

    if (hasVector) {
      baseColumns.push({
        key: VECTOR_FIELD,
        label: "Vector",
        render: (value) => (
          <span className={styles.vectorPreview}>{truncateVector(value)}</span>
        ),
      });
    }

    return baseColumns;
  }, [propColumns, records, hasScores, hasVector]);

  const getValue = useCallback((record: ScoredRecord, key: string): FieldValue | undefined => {
    if (key === ID_KEY) return record.id;
    if (key === SCORE_KEY) return record.score ?? null;
    return record.fields[key];
  }, []);

  const sortedRecords = useMemo(() => {
    if (!sortKey) {
      return records;
    }
    return [...records].sort((a, b) => {
      const cmp = compareValues(getValue(a, sortKey), getValue(b, sortKey));
      return sortDir === "asc" ? cmp : -cmp;
    });
  }, [records, sortKey, sortDir, getValue]);

  const pagedRecords = useMemo(() => {
    const start = page * pageSize;
    return sortedRecords.slice(start, start + pageSize);
  }, [sortedRecords, page, pageSize]);

  const totalPages = Math.ceil(records.length / pageSize);

  const handleSort = useCallback(
    (key: string) => {
      if (sortKey === key) {
        setSortDir((d) => (d === "asc" ? "desc" : "asc"));
      } else {
        setSortKey(key);
        setSortDir("asc");
      }
    },
    [sortKey],
  );

  return (
    <div className={styles.container}>
      <div className={styles.tableWrapper}>
        <table className={styles.table}>
          <thead>
            <tr>
              {columns.map((col) => (
                <th
                  key={col.key}
                  className={styles.th}
                  style={{ width: col.width }}
                  onClick={() => handleSort(col.key)}
                >
                  <span className={styles.thContent}>
                    {col.label}
                    {sortKey === col.key && (
                      <span className={styles.sortIcon}>
                        {sortDir === "asc" ? "↑" : "↓"}
                      </span>
                    )}
                  </span>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            <TableBodyContent
              loading={loading}
              pagedRecords={pagedRecords}
              columns={columns}
              selectedId={selectedId}
              onSelect={onSelect}
              onDoubleClick={onDoubleClick}
              getValue={getValue}
            />
          </tbody>
        </table>
      </div>

      {totalPages > 1 && (
        <div className={styles.pagination}>
          <button
            className={styles.pageBtn}
            disabled={page === 0}
            onClick={() => setPage(0)}
          >
            «
          </button>
          <button
            className={styles.pageBtn}
            disabled={page === 0}
            onClick={() => setPage((p) => Math.max(0, p - 1))}
          >
            ‹
          </button>
          <span className={styles.pageInfo}>
            Page {page + 1} of {totalPages} ({records.length} rows)
          </span>
          <button
            className={styles.pageBtn}
            disabled={page >= totalPages - 1}
            onClick={() => setPage((p) => Math.min(totalPages - 1, p + 1))}
          >
            ›
          </button>
          <button
            className={styles.pageBtn}
            disabled={page >= totalPages - 1}
            onClick={() => setPage(totalPages - 1)}
          >
            »
          </button>
        </div>
      )}
    </div>
  );
}

export type { DataRecord };
