import React, { useMemo, useState, useCallback } from "react";
import styles from "./DataTable.module.css";

type Column = {
  key: string;
  label: string;
  width?: number;
  render?: (value: unknown, row: DataRow) => React.ReactNode;
};

type DataRow = {
  id: number;
  score?: number;
  attrs: Record<string, unknown> | null;
  vector?: number[];
};

type DataTableProps = {
  data: DataRow[];
  columns?: Column[];
  selectedId?: number | null;
  onSelect?: (row: DataRow) => void;
  onDoubleClick?: (row: DataRow) => void;
  pageSize?: number;
  loading?: boolean;
};

function renderCellValue(col: Column, value: unknown, row: DataRow): React.ReactNode {
  if (col.render) {
    return col.render(value, row);
  }
  return formatValue(value);
}

type TableBodyContentProps = {
  loading: boolean;
  pagedData: DataRow[];
  columns: Column[];
  selectedId?: number | null;
  onSelect?: (row: DataRow) => void;
  onDoubleClick?: (row: DataRow) => void;
  getValue: (row: DataRow, key: string) => unknown;
};

function TableBodyContent({
  loading,
  pagedData,
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
  if (pagedData.length === 0) {
    return (
      <tr>
        <td colSpan={columns.length} className={styles.empty}>
          No data
        </td>
      </tr>
    );
  }
  return pagedData.map((row, i) => (
    <tr
      key={row.id}
      className={styles.tr}
      data-row-id={row.id}
      data-odd={i % 2 === 1}
      data-selected={selectedId === row.id}
      onClick={() => onSelect?.(row)}
      onDoubleClick={() => onDoubleClick?.(row)}
    >
      {columns.map((col) => (
        <td key={col.key} className={styles.td}>
          {renderCellValue(col, getValue(row, col.key), row)}
        </td>
      ))}
    </tr>
  ));
}

function truncateVector(vector: number[] | undefined): string {
  if (!vector || vector.length === 0) {
    return "[]";
  }
  const preview = vector.slice(0, 4).map((v) => v.toFixed(3));
  if (vector.length > 4) {
    return `[${preview.join(", ")}, ...]`;
  }
  return `[${preview.join(", ")}]`;
}

function formatValue(value: unknown): string {
  if (value === null || value === undefined) {
    return "-";
  }
  if (typeof value === "object") {
    return JSON.stringify(value);
  }
  return String(value);
}

export function DataTable({
  data,
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

  // Auto-detect columns from first row's attrs
  const columns = useMemo<Column[]>(() => {
    if (propColumns) {
      return propColumns;
    }

    const baseColumns: Column[] = [
      { key: "id", label: "ID", width: 80 },
      { key: "score", label: "Score", width: 100 },
    ];

    // Collect all unique attr keys from data
    const attrKeys = new Set<string>();
    for (const row of data) {
      if (row.attrs) {
        for (const key of Object.keys(row.attrs)) {
          attrKeys.add(key);
        }
      }
    }

    const attrColumns: Column[] = Array.from(attrKeys).map((key) => ({
      key: `attrs.${key}`,
      label: key,
    }));

    baseColumns.push(...attrColumns);
    baseColumns.push({
      key: "vector",
      label: "Vector",
      render: (_, row) => (
        <span className={styles.vectorPreview}>
          {truncateVector(row.vector)}
        </span>
      ),
    });

    return baseColumns;
  }, [propColumns, data]);

  // Sort data
  const sortedData = useMemo(() => {
    if (!sortKey) {
      return data;
    }

    return [...data].sort((a, b) => {
      let aVal: unknown;
      let bVal: unknown;

      if (sortKey.startsWith("attrs.")) {
        const attrKey = sortKey.slice(6);
        aVal = a.attrs?.[attrKey];
        bVal = b.attrs?.[attrKey];
      } else if (sortKey === "id") {
        aVal = a.id;
        bVal = b.id;
      } else if (sortKey === "score") {
        aVal = a.score;
        bVal = b.score;
      }

      if (aVal === bVal) {
        return 0;
      }
      if (aVal === null || aVal === undefined) {
        return 1;
      }
      if (bVal === null || bVal === undefined) {
        return -1;
      }

      const cmp = aVal < bVal ? -1 : 1;
      return sortDir === "asc" ? cmp : -cmp;
    });
  }, [data, sortKey, sortDir]);

  // Paginate
  const pagedData = useMemo(() => {
    const start = page * pageSize;
    return sortedData.slice(start, start + pageSize);
  }, [sortedData, page, pageSize]);

  const totalPages = Math.ceil(data.length / pageSize);

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

  const getValue = (row: DataRow, key: string): unknown => {
    if (key.startsWith("attrs.")) {
      const attrKey = key.slice(6);
      return row.attrs?.[attrKey];
    }
    if (key === "id") {
      return row.id;
    }
    if (key === "score") {
      return row.score;
    }
    if (key === "vector") {
      return row.vector;
    }
    return undefined;
  };

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
              pagedData={pagedData}
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
            Page {page + 1} of {totalPages} ({data.length} rows)
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
