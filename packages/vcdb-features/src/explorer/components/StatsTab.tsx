import { useDatabase } from "../../context/DatabaseContext";
import { Button } from "@vcdb/ui-kit";
import { useToast } from "@vcdb/ui-kit/toast";
import styles from "./StatsTab.module.css";

export function StatsTab() {
  const { stats, refresh } = useDatabase();
  const toast = useToast();

  if (!stats) {
    return (
      <div className={styles.empty}>
        <p>No statistics available</p>
      </div>
    );
  }

  return (
    <div className={styles.container}>
      <div className={styles.card}>
        <h3 className={styles.title}>Collection Statistics</h3>

        <div className={styles.stats}>
          <div className={styles.stat}>
            <span className={styles.label}>Vectors</span>
            <span className={styles.value}>{stats.size.toLocaleString()}</span>
          </div>
          <div className={styles.stat}>
            <span className={styles.label}>Dimensions</span>
            <span className={styles.value}>{stats.dim}</span>
          </div>
          <div className={styles.stat}>
            <span className={styles.label}>Metric</span>
            <span className={styles.value}>{stats.metric}</span>
          </div>
          <div className={styles.stat}>
            <span className={styles.label}>Strategy</span>
            <span className={styles.value}>{stats.strategy}</span>
          </div>
        </div>

        <div className={styles.actions}>
          <Button size="sm" onClick={() => {
            refresh();
            toast.success("Statistics refreshed");
          }}>
            Refresh
          </Button>
        </div>
      </div>
    </div>
  );
}
