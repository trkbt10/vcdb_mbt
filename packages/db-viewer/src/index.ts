// @vcdb/db-viewer — generic React components for browsing record-shaped data,
// driven by the DataSource interface from @vcdb/data-source. No vcdb-specific
// knowledge — reusable for indexion-style use cases.

export { DataTable, type Column, type DataTableProps } from "./DataTable.tsx";
export type {
  DataRecord,
  ScoredRecord,
  RecordId,
  FieldValue,
} from "@vcdb/data-source";
