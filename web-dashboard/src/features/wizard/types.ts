/**
 * @file Wizard-specific types only
 *
 * Components should import vcdb types directly from their source:
 *   - "vcdb/types/public" for DatabaseOptions, Metric, etc.
 *   - "vcdb/meta/index-types" for IndexConfig, VectorIndexConfig, etc.
 *   - "vcdb/attr/types" for FieldDef, AttrOp, etc.
 *   - "vcdb/config/types-public" for RawStorageConfig, RawAppConfig, etc.
 */

import type { IndexConfig } from "vcdb/meta/index-types";
import type { RawStorageConfig } from "vcdb/config/types-public";
import type { DatabaseOptions } from "vcdb/types/public";

/** Named index entry for UI display */
export type IndexEntry = {
  name: string;
  config: IndexConfig;
};

/** Server connection configuration */
export type ServerConfig = {
  host: string;
  port: number;
};

/**
 * WizardData is the wizard's working state.
 * All fields required for editing; produces RawAppConfig on export.
 */
export type WizardData = {
  name: string;
  storage: RawStorageConfig;
  database: DatabaseOptions;
  indexes: Record<string, IndexConfig>;
  server: ServerConfig;
};
