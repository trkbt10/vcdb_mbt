import styles from "./StatusBadge.module.css";

type ConnectionStatus = "online" | "offline" | "unknown" | "loading";
type IndexStatus = "ready" | "pending" | "building" | "error";
type Status = ConnectionStatus | IndexStatus;
type StatusVariant = "success" | "warning" | "error" | "info" | "default";

type StatusBadgeProps = {
  status: Status;
  variant?: StatusVariant;
  showLabel?: boolean;
  size?: "sm" | "md";
  title?: string;
};

const labels: Record<Status, string> = {
  online: "Online",
  offline: "Offline",
  unknown: "Unknown",
  loading: "Connecting",
  ready: "Ready",
  pending: "Pending",
  building: "Building",
  error: "Error",
};

const defaultVariants: Record<Status, StatusVariant> = {
  online: "success",
  offline: "error",
  unknown: "default",
  loading: "info",
  ready: "success",
  pending: "info",
  building: "warning",
  error: "error",
};

export function StatusBadge({
  status,
  variant,
  showLabel = false,
  size = "md",
  title,
}: StatusBadgeProps) {
  const resolvedVariant = variant ?? defaultVariants[status];

  return (
    <span
      className={styles.badge}
      data-status={status}
      data-variant={resolvedVariant}
      data-size={size}
      title={title ?? labels[status]}
    >
      <span className={styles.dot} />
      {showLabel && <span className={styles.label}>{labels[status]}</span>}
    </span>
  );
}
