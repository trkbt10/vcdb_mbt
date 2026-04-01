import React, { forwardRef, type ButtonHTMLAttributes, type ReactNode } from "react";
import styles from "./Button.module.css";

type ButtonVariant = "primary" | "secondary" | "ghost" | "danger";
type ButtonSize = "sm" | "md" | "lg";

type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: ButtonVariant;
  size?: ButtonSize;
  loading?: boolean;
  icon?: ReactNode;
  children?: ReactNode;
};

function ButtonIconContent({ loading, icon }: { loading: boolean; icon?: ReactNode }): React.ReactNode {
  if (loading) {
    return <span className={styles.spinner} />;
  }
  if (icon) {
    return <span className={styles.icon}>{icon}</span>;
  }
  return null;
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  function Button(
    {
      variant = "secondary",
      size = "md",
      loading = false,
      icon,
      children,
      className,
      disabled,
      ...props
    },
    ref,
  ) {
    const classNames = [
      styles.button,
      styles[variant],
      styles[size],
      loading ? styles.loading : "",
      className ?? "",
    ]
      .filter(Boolean)
      .join(" ");

    return (
      <button
        ref={ref}
        className={classNames}
        disabled={disabled || loading}
        {...props}
      >
        <ButtonIconContent loading={loading} icon={icon} />
        {children && <span className={styles.label}>{children}</span>}
      </button>
    );
  },
);
