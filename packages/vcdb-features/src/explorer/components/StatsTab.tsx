import { useDatabase } from "../../context/DatabaseContext";
import { Button } from "@vcdb/ui-kit";
import { useToast } from "@vcdb/ui-kit/toast";
import { StatsList } from "./StatsList";
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
        <StatsList stats={stats} variant="roomy" />
        <div className={styles.actions}>
          <Button
            size="sm"
            onClick={() => {
              refresh();
              toast.success("Statistics refreshed");
            }}
          >
            Refresh
          </Button>
        </div>
      </div>
    </div>
  );
}
