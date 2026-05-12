import { useDatabase } from "../../context/DatabaseContext";
import { Button } from "@vcdb/ui-kit";
import { useAsyncFn } from "react-use";
import { useToast } from "@vcdb/ui-kit/toast";
import { StatsList } from "./StatsList";
import styles from "./StatsPanel.module.css";

export function StatsPanel() {
  const { stats, save, refresh } = useDatabase();
  const toast = useToast();

  const [saveState, handleSave] = useAsyncFn(async () => {
    const result = await save();
    if (result.ok) {
      toast.success("Database saved successfully");
    } else {
      toast.error("Failed to save database");
    }
    return result;
  }, [save, toast]);

  if (!stats) {
    return null;
  }

  return (
    <div className={styles.panel}>
      <h3 className={styles.title}>Database Stats</h3>
      <StatsList stats={stats} variant="compact" />
      <div className={styles.actions}>
        <Button size="sm" onClick={refresh}>
          Refresh
        </Button>
        <Button
          size="sm"
          variant="primary"
          onClick={handleSave}
          loading={saveState.loading}
        >
          Save
        </Button>
      </div>
    </div>
  );
}
