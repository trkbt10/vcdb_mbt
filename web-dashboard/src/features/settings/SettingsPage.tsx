import { useTheme } from "@vcdb/ui-kit/theme";
import { useDatabase } from "@/contexts/DatabaseContext";
import { Button, PageHeader, ArrowLeft } from "@vcdb/ui-kit";
import styles from "./SettingsPage.module.css";

type SettingsPageProps = {
  onClose: () => void;
};

export function SettingsPage({ onClose }: SettingsPageProps) {
  const { theme, toggle } = useTheme();
  const { databaseName, disconnect } = useDatabase();

  const handleDisconnect = () => {
    disconnect();
    onClose();
  };

  return (
    <div className={styles.page}>
      <PageHeader
        title="Settings"
        subtitle="Configure your dashboard preferences"
        backButton={
          <button className={styles.backButton} onClick={onClose}>
            <ArrowLeft size={16} />
            <span>Back</span>
          </button>
        }
      />

      <div className={styles.content}>
        <section className={styles.section}>
          <h2 className={styles.sectionTitle}>Appearance</h2>
          <div className={styles.setting}>
            <div className={styles.settingInfo}>
              <label>Theme</label>
              <p className={styles.description}>
                Switch between light and dark mode
              </p>
            </div>
            <Button onClick={toggle}>
              {theme === "light" ? "Dark Mode" : "Light Mode"}
            </Button>
          </div>
        </section>

        {databaseName && (
          <section className={styles.section}>
            <h2 className={styles.sectionTitle}>Connection</h2>
            <div className={styles.setting}>
              <div className={styles.settingInfo}>
                <label>Current Database</label>
                <p className={styles.description}>
                  Connected to: {databaseName}
                </p>
              </div>
              <Button variant="ghost" onClick={handleDisconnect}>
                Disconnect
              </Button>
            </div>
          </section>
        )}
      </div>
    </div>
  );
}
