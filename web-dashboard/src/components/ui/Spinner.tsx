import styles from "./Spinner.module.css";

type SpinnerProps = {
  size?: "sm" | "md" | "lg";
};

export function Spinner({ size = "md" }: SpinnerProps) {
  return (
    <div
      className={styles.spinner}
      data-size={size}
      role="status"
      aria-label="Loading"
    />
  );
}
