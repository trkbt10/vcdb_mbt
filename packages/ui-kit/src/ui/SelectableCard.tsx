import type { ReactNode } from "react";
import { Check } from "./Icon";
import styles from "./SelectableCard.module.css";

type SelectableCardProps = {
  selected: boolean;
  onClick: () => void;
  title: string;
  description?: string;
  tags?: string[];
  children?: ReactNode;
};

export function SelectableCard({
  selected,
  onClick,
  title,
  description,
  tags,
  children,
}: SelectableCardProps) {
  return (
    <button
      type="button"
      className={styles.card}
      data-selected={selected}
      onClick={onClick}
    >
      <div className={styles.header}>
        <span className={styles.title}>{title}</span>
        {selected && (
          <span className={styles.badge}>
            <Check size={12} />
          </span>
        )}
      </div>
      {description && <p className={styles.description}>{description}</p>}
      {tags && tags.length > 0 && (
        <div className={styles.tags}>
          {tags.map((tag) => (
            <span key={tag} className={styles.tag}>
              {tag}
            </span>
          ))}
        </div>
      )}
      {children}
    </button>
  );
}
