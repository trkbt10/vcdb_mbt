import { useTheme } from "@vcdb/ui-kit/theme";
import { Logo, Sun, Moon } from "@vcdb/ui-kit";
import type { DatabaseInfo } from "@/features/registry/components";
import styles from "./Header.module.css";

type HeaderProps = {
  selectedDb: DatabaseInfo | null;
};

export function Header({ selectedDb }: HeaderProps) {
  const { theme, toggle } = useTheme();

  return (
    <header className={styles.header}>
      <div className={styles.left}>
        <div className={styles.logo}>
          <Logo size={24} />
          <span className={styles.title}>vcdb</span>
        </div>
        {selectedDb && (
          <div className={styles.breadcrumb}>
            <span className={styles.separator}>/</span>
            <span className={styles.dbName}>{selectedDb.name}</span>
          </div>
        )}
      </div>

      <div className={styles.right}>
        <button
          className={styles.themeToggle}
          onClick={toggle}
          title={`Switch to ${theme === "light" ? "dark" : "light"} mode`}
        >
          {theme === "light" ? <Moon size={18} /> : <Sun size={18} />}
        </button>
      </div>
    </header>
  );
}
