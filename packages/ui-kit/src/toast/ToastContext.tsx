import {
  createContext,
  useContext,
  useState,
  useCallback,
  useMemo,
  type ReactNode,
} from "react";

type ToastType = "info" | "success" | "warning" | "error";

type Toast = {
  id: string;
  type: ToastType;
  message: string;
  duration: number;
};

type ToastContextValue = {
  toasts: Toast[];
  addToast: (toast: Omit<Toast, "id">) => void;
  removeToast: (id: string) => void;
  showToast: (message: string, type?: ToastType) => void;
  info: (message: string) => void;
  success: (message: string) => void;
  warning: (message: string) => void;
  error: (message: string) => void;
};

const ToastContext = createContext<ToastContextValue | null>(null);

const DEFAULT_DURATION = 4000;

function generateId(): string {
  return `toast-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
}

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);

  const removeToast = useCallback((id: string) => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
  }, []);

  const addToast = useCallback(
    (toast: Omit<Toast, "id">) => {
      const id = generateId();
      const newToast: Toast = { id, ...toast };

      setToasts((prev) => [...prev, newToast]);

      if (toast.duration > 0) {
        setTimeout(() => {
          removeToast(id);
        }, toast.duration);
      }
    },
    [removeToast],
  );

  const info = useCallback(
    (message: string) => {
      addToast({ type: "info", message, duration: DEFAULT_DURATION });
    },
    [addToast],
  );

  const success = useCallback(
    (message: string) => {
      addToast({ type: "success", message, duration: DEFAULT_DURATION });
    },
    [addToast],
  );

  const warning = useCallback(
    (message: string) => {
      addToast({ type: "warning", message, duration: DEFAULT_DURATION });
    },
    [addToast],
  );

  const error = useCallback(
    (message: string) => {
      addToast({ type: "error", message, duration: DEFAULT_DURATION * 1.5 });
    },
    [addToast],
  );

  const showToast = useCallback(
    (message: string, type: ToastType = "info") => {
      const duration =
        type === "error" ? DEFAULT_DURATION * 1.5 : DEFAULT_DURATION;
      addToast({ type, message, duration });
    },
    [addToast],
  );

  const value = useMemo<ToastContextValue>(
    () => ({
      toasts,
      addToast,
      removeToast,
      showToast,
      info,
      success,
      warning,
      error,
    }),
    [toasts, addToast, removeToast, showToast, info, success, warning, error],
  );

  return (
    <ToastContext.Provider value={value}>{children}</ToastContext.Provider>
  );
}

export function useToast(): ToastContextValue {
  const ctx = useContext(ToastContext);
  if (!ctx) {
    throw new Error("useToast must be used within ToastProvider");
  }
  return ctx;
}
