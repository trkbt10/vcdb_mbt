import { ConnectionManager, type DatabaseInfo } from "@/features/registry/components";
import styles from "./Sidebar.module.css";

type SidebarProps = {
  selectedId: string | null;
  onSelect: (db: DatabaseInfo) => void;
};

export function Sidebar({ selectedId, onSelect }: SidebarProps) {
  return (
    <aside className={styles.sidebar}>
      <ConnectionManager mode="compact" selectedId={selectedId} onSelect={onSelect} />
    </aside>
  );
}
