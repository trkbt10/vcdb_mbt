import { useState, useEffect, useCallback } from "react";
import type { DashboardConfig } from "../types.ts";

type UseServerConfigResult = {
  config: DashboardConfig | null;
  loading: boolean;
  saving: boolean;
  error: string | null;
  update: (partial: Partial<DashboardConfig>) => Promise<void>;
  refresh: () => Promise<void>;
};

/**
 * Hook for managing dashboard server configuration.
 */
export function useServerConfig(): UseServerConfigResult {
  const [config, setConfig] = useState<DashboardConfig | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchConfig = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const res = await fetch("/api/config/dashboard");
      if (!res.ok) {
        throw new Error(`Failed to fetch config: ${res.status}`);
      }
      const data = await res.json();
      setConfig(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error");
    } finally {
      setLoading(false);
    }
  }, []);

  const update = useCallback(async (partial: Partial<DashboardConfig>) => {
    try {
      setSaving(true);
      setError(null);
      const res = await fetch("/api/config/dashboard", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(partial),
      });
      if (!res.ok) {
        throw new Error(`Failed to update config: ${res.status}`);
      }
      const data = await res.json();
      setConfig(data.config);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error");
      throw err;
    } finally {
      setSaving(false);
    }
  }, []);

  useEffect(() => {
    void fetchConfig();
  }, [fetchConfig]);

  return { config, loading, saving, error, update, refresh: fetchConfig };
}
