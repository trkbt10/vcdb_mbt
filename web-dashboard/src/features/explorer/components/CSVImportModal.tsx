import { useState, useCallback, useRef } from "react";
import { Modal, Button, Select } from "@/components/ui";
import { useDatabase } from "@/contexts/DatabaseContext";
import { useToast } from "@/contexts/ToastContext";
import { useAsyncFn } from "react-use";
import styles from "./CSVImportModal.module.css";

type CSVImportModalProps = {
  isOpen: boolean;
  onClose: () => void;
  onSuccess?: () => void;
};

type ParsedRow = {
  [key: string]: string;
};

export function CSVImportModal({ isOpen, onClose, onSuccess }: CSVImportModalProps) {
  const { bulkUpsert, stats } = useDatabase();
  const toast = useToast();
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [file, setFile] = useState<File | null>(null);
  const [headers, setHeaders] = useState<string[]>([]);
  const [rows, setRows] = useState<ParsedRow[]>([]);
  const [idColumn, setIdColumn] = useState("");
  const [vectorColumn, setVectorColumn] = useState("");

  const parseCSV = useCallback((text: string): { headers: string[]; rows: ParsedRow[] } => {
    const lines = text.trim().split("\n");
    if (lines.length === 0) {
      return { headers: [], rows: [] };
    }

    const headerLine = lines[0];
    const headers = headerLine.split(",").map((h) => h.trim().replace(/^"|"$/g, ""));

    const rows: ParsedRow[] = [];
    for (let i = 1; i < lines.length; i++) {
      const values = lines[i].split(",").map((v) => v.trim().replace(/^"|"$/g, ""));
      const row: ParsedRow = {};
      headers.forEach((header, idx) => {
        row[header] = values[idx] ?? "";
      });
      rows.push(row);
    }

    return { headers, rows };
  }, []);

  const handleFileChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const selectedFile = e.target.files?.[0];
      if (!selectedFile) {
        return;
      }

      setFile(selectedFile);
      const reader = new FileReader();
      reader.onload = (event) => {
        const text = event.target?.result as string;
        const { headers, rows } = parseCSV(text);
        setHeaders(headers);
        setRows(rows);

        // Auto-detect columns
        if (headers.includes("id")) {
          setIdColumn("id");
        }
        if (headers.includes("vector")) {
          setVectorColumn("vector");
        }
      };
      reader.readAsText(selectedFile);
    },
    [parseCSV],
  );

  const [importState, handleImport] = useAsyncFn(async () => {
    if (!idColumn || !vectorColumn) {
      toast.error("Please select ID and Vector columns");
      return;
    }

    const data = rows.map((row) => {
      const id = parseInt(row[idColumn], 10);

      // Parse vector from string
      let vector: number[];
      try {
        const vectorStr = row[vectorColumn];
        if (vectorStr.startsWith("[")) {
          vector = JSON.parse(vectorStr);
        } else {
          vector = vectorStr.split(",").map((v) => parseFloat(v.trim()));
        }
      } catch {
        vector = [];
      }

      // Get attrs (all columns except id and vector)
      const attrs: Record<string, string | number | boolean | null> = {};
      for (const [key, value] of Object.entries(row)) {
        if (key === idColumn || key === vectorColumn) {
          continue;
        }
        // Try to parse as JSON, fallback to string
        try {
          const parsed = JSON.parse(value);
          if (
            typeof parsed === "string" ||
            typeof parsed === "number" ||
            typeof parsed === "boolean" ||
            parsed === null
          ) {
            attrs[key] = parsed;
          } else {
            attrs[key] = value;
          }
        } catch {
          attrs[key] = value;
        }
      }

      return { id, vector, attrs };
    });

    // Validate vectors
    const validData = data.filter((d) => !Number.isNaN(d.id) && d.vector.length > 0);
    if (validData.length === 0) {
      toast.error("No valid rows to import");
      return;
    }

    // Check dimension match
    if (stats && validData.some((d) => d.vector.length !== stats.dim)) {
      toast.error(`All vectors must have ${stats.dim} dimensions`);
      return;
    }

    try {
      const result = await bulkUpsert(validData);
      const successCount = result.results.filter((r) => r.ok).length;
      toast.success(`Imported ${successCount} of ${validData.length} rows`);
      onSuccess?.();
      handleClose();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Import failed");
    }
  }, [rows, idColumn, vectorColumn, stats, bulkUpsert, toast, onSuccess]);

  const handleClose = () => {
    setFile(null);
    setHeaders([]);
    setRows([]);
    setIdColumn("");
    setVectorColumn("");
    if (fileInputRef.current) {
      fileInputRef.current.value = "";
    }
    onClose();
  };

  const columnOptions = [{ value: "", label: "Select column..." }, ...headers.map((h) => ({ value: h, label: h }))];
  const attrColumns = headers.filter((h) => h !== idColumn && h !== vectorColumn);

  const footer = (
    <div className={styles.footer}>
      <Button variant="ghost" onClick={handleClose}>
        Cancel
      </Button>
      <Button
        variant="primary"
        onClick={handleImport}
        loading={importState.loading}
        disabled={!file || !idColumn || !vectorColumn}
      >
        Import {rows.length} Rows
      </Button>
    </div>
  );

  return (
    <Modal open={isOpen} onClose={handleClose} title="Import from CSV" footer={footer}>
      <div className={styles.content}>
        <div className={styles.field}>
          <label className={styles.label}>CSV File</label>
          <input
            ref={fileInputRef}
            type="file"
            accept=".csv"
            onChange={handleFileChange}
            className={styles.fileInput}
          />
        </div>

        {headers.length > 0 && (
          <>
            <div className={styles.preview}>
              <span className={styles.previewLabel}>
                Found {rows.length} rows with {headers.length} columns
              </span>
            </div>

            <div className={styles.mapping}>
              <div className={styles.field}>
                <label className={styles.label}>ID Column</label>
                <Select
                  value={idColumn}
                  onChange={(e) => setIdColumn(e.target.value)}
                  options={columnOptions}
                />
              </div>

              <div className={styles.field}>
                <label className={styles.label}>Vector Column</label>
                <Select
                  value={vectorColumn}
                  onChange={(e) => setVectorColumn(e.target.value)}
                  options={columnOptions}
                />
                <span className={styles.hint}>
                  Format: comma-separated or JSON array
                  {stats && ` (${stats.dim} dimensions)`}
                </span>
              </div>

              {attrColumns.length > 0 && (
                <div className={styles.field}>
                  <label className={styles.label}>Attribute Columns</label>
                  <span className={styles.attrList}>{attrColumns.join(", ")}</span>
                </div>
              )}
            </div>
          </>
        )}
      </div>
    </Modal>
  );
}
