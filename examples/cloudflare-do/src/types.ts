/**
 * @file Cloudflare environment bindings for the DO example.
 */
import type { VcdbStore } from "./infra/vcdb-do.ts";

export type Bindings = {
  /** R2 bucket for vcdb snapshot storage. */
  VCDB_DATA: R2Bucket;
  /** Durable Object namespace for vcdb shards. */
  VCDB_STORE: DurableObjectNamespace<VcdbStore>;
};
