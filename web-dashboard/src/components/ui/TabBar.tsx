import type { ReactNode } from "react";
import styles from "./TabBar.module.css";

export type TabItem = {
  id: string;
  label: string;
  icon?: ReactNode;
};

type TabBarProps = {
  tabs: TabItem[];
  activeTab: string;
  onTabChange: (tabId: string) => void;
  className?: string;
};

export function TabBar({ tabs, activeTab, onTabChange, className }: TabBarProps) {
  const classNames = [styles.tabBar, className].filter(Boolean).join(" ");

  return (
    <div className={classNames} role="tablist">
      {tabs.map((tab) => {
        const isActive = tab.id === activeTab;
        const tabClasses = [styles.tab, isActive ? styles.active : ""]
          .filter(Boolean)
          .join(" ");

        return (
          <button
            key={tab.id}
            role="tab"
            aria-selected={isActive}
            className={tabClasses}
            onClick={() => onTabChange(tab.id)}
          >
            {tab.icon && <span className={styles.icon}>{tab.icon}</span>}
            <span className={styles.label}>{tab.label}</span>
          </button>
        );
      })}
    </div>
  );
}
