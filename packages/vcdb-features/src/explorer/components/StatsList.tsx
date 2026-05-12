import type { CollectionStats } from "@vcdb/api-client";
import styles from "./StatsList.module.css";

export type StatsListVariant = "compact" | "roomy";

export type StatsListProps = {
  stats: CollectionStats;
  /** Visual density. `compact` for in-panel use, `roomy` for full-page tabs. */
  variant?: StatsListVariant;
};

/**
 * Shared 4-up grid of collection stats (Vectors / Dimensions / Metric /
 * Strategy). Both the sidebar panel and the stats tab compose this so a
 * new stat is added in one place.
 */
export function StatsList({ stats, variant = "compact" }: StatsListProps) {
  return (
    <div className={styles.stats} data-variant={variant}>
      <Stat label="Vectors" value={stats.size.toLocaleString()} />
      <Stat label="Dimensions" value={stats.dim} />
      <Stat label="Metric" value={stats.metric} />
      <Stat label="Strategy" value={stats.strategy} />
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string | number }) {
  return (
    <div className={styles.stat}>
      <span className={styles.label}>{label}</span>
      <span className={styles.value}>{value}</span>
    </div>
  );
}
