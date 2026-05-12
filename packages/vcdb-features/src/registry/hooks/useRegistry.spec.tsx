/**
 * @file Tests for useRegistry hook
 */
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { renderHook, waitFor, act } from "@testing-library/react";
import type { ReactNode } from "react";
import { RegistryProvider, useRegistry } from "./useRegistry";

// Mock fetch
const originalFetch = globalThis.fetch;

function createMockFetch(responses: Record<string, { ok: boolean; data?: unknown; status?: number }>) {
  return vi.fn((input: RequestInfo | URL, options?: RequestInit) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
    const method = options?.method ?? "GET";
    const key = `${method} ${url}`;

    // Find matching response
    for (const [pattern, response] of Object.entries(responses)) {
      if (key.includes(pattern) || url.includes(pattern)) {
        return Promise.resolve({
          ok: response.ok,
          status: response.status ?? (response.ok ? 200 : 500),
          json: () => Promise.resolve(response.data ?? {}),
        } as Response);
      }
    }

    // Default 404
    return Promise.resolve({
      ok: false,
      status: 404,
      json: () => Promise.resolve({ error: { message: "Not found" } }),
    } as Response);
  });
}

function wrapper({ children }: { children: ReactNode }) {
  return <RegistryProvider>{children}</RegistryProvider>;
}

describe("useRegistry", () => {
  beforeEach(() => {
    // Reset fetch mock before each test
    globalThis.fetch = originalFetch;
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
  });

  it("should fetch databases on mount", async () => {
    const mockFetch = createMockFetch({
      "/api/databases": {
        ok: true,
        data: {
          databases: [
            { name: "db1", size: 100, dim: 384, metric: "cosine", strategy: "hnsw" },
            { name: "db2", size: 200, dim: 128, metric: "l2", strategy: "bruteforce" },
          ],
        },
      },
    });
    globalThis.fetch = mockFetch;

    const { result } = renderHook(() => useRegistry(), { wrapper });

    // Wait for loading to complete
    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(result.current.databases).toHaveLength(2);
    expect(result.current.databases[0].name).toBe("db1");
    expect(result.current.databases[1].name).toBe("db2");
    expect(result.current.error).toBeNull();
  });

  it("should handle fetch error", async () => {
    const mockFetch = createMockFetch({
      "/api/databases": {
        ok: false,
        status: 500,
        data: { error: { message: "Server error" } },
      },
    });
    globalThis.fetch = mockFetch;

    const { result } = renderHook(() => useRegistry(), { wrapper });

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(result.current.databases).toHaveLength(0);
    expect(result.current.error).toBe("Server error");
  });

  it("should create database", async () => {
    const mockFetch = createMockFetch({
      "GET /api/databases": {
        ok: true,
        data: { databases: [] },
      },
      "POST /api/databases": {
        ok: true,
        data: { ok: true },
      },
    });
    globalThis.fetch = mockFetch;

    const { result } = renderHook(() => useRegistry(), { wrapper });

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    await act(async () => {
      await result.current.createDatabase({
        name: "new-db",
        config: { dim: 384, metric: "cosine", strategy: "hnsw" },
      });
    });

    // Verify POST was called
    expect(mockFetch).toHaveBeenCalledWith(
      "/api/databases",
      expect.objectContaining({
        method: "POST",
        headers: { "Content-Type": "application/json" },
      }),
    );
  });

  it("should delete database", async () => {
    const mockFetch = createMockFetch({
      "GET /api/databases": {
        ok: true,
        data: {
          databases: [{ name: "to-delete", size: 0, dim: 384, metric: "cosine", strategy: "hnsw" }],
        },
      },
      "DELETE /api/databases/to-delete": {
        ok: true,
        data: { ok: true },
      },
    });
    globalThis.fetch = mockFetch;

    const { result } = renderHook(() => useRegistry(), { wrapper });

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    await act(async () => {
      await result.current.deleteDatabase("to-delete");
    });

    // Verify DELETE was called
    expect(mockFetch).toHaveBeenCalledWith(
      "/api/databases/to-delete",
      expect.objectContaining({ method: "DELETE" }),
    );
  });

  it("should handle create error", async () => {
    const mockFetch = createMockFetch({
      "GET /api/databases": {
        ok: true,
        data: { databases: [] },
      },
      "POST /api/databases": {
        ok: false,
        status: 400,
        data: { error: { message: "Database already exists" } },
      },
    });
    globalThis.fetch = mockFetch;

    const { result } = renderHook(() => useRegistry(), { wrapper });

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    await expect(
      act(async () => {
        await result.current.createDatabase({
          name: "existing-db",
          config: { dim: 384 },
        });
      }),
    ).rejects.toThrow("Database already exists");
  });

  it("should refresh databases", async () => {
    const tracker = { count: 0 };
    const mockFetch = vi.fn((input: RequestInfo | URL) => {
      const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
      if (url.includes("/api/databases")) {
        tracker.count++;
        return Promise.resolve({
          ok: true,
          status: 200,
          json: () => Promise.resolve({ databases: [] }),
        } as Response);
      }
      return Promise.resolve({
        ok: false,
        status: 404,
        json: () => Promise.resolve({}),
      } as Response);
    });
    globalThis.fetch = mockFetch;

    const { result } = renderHook(() => useRegistry(), { wrapper });

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    const initialCount = tracker.count;

    await act(async () => {
      await result.current.refresh();
    });

    expect(tracker.count).toBeGreaterThan(initialCount);
  });
});
