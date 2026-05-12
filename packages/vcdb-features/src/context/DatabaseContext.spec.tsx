/**
 * @file Tests for DatabaseContext
 */
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { renderHook, waitFor, act } from "@testing-library/react";
import type { ReactNode } from "react";
import { DatabaseProvider, useDatabase } from "./DatabaseContext";

const originalFetch = globalThis.fetch;

function createMockFetch(responses: Record<string, { ok: boolean; data?: unknown; status?: number }>) {
  return vi.fn((input: RequestInfo | URL, _init?: RequestInit) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
    for (const [pattern, response] of Object.entries(responses)) {
      if (url.includes(pattern)) {
        return Promise.resolve({
          ok: response.ok,
          status: response.status ?? (response.ok ? 200 : 500),
          json: () => Promise.resolve(response.data ?? {}),
        } as Response);
      }
    }

    return Promise.resolve({
      ok: false,
      status: 404,
      json: () => Promise.resolve({ error: { message: "Not found" } }),
    } as Response);
  });
}

function wrapper({ children }: { children: ReactNode }) {
  return <DatabaseProvider>{children}</DatabaseProvider>;
}

describe("DatabaseContext", () => {
  beforeEach(() => {
    globalThis.fetch = originalFetch;
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
  });

  it("should start with no database selected", () => {
    const { result } = renderHook(() => useDatabase(), { wrapper });

    expect(result.current.databaseName).toBeNull();
    expect(result.current.isConnected).toBe(false);
    expect(result.current.stats).toBeNull();
  });

  it("should select database and fetch stats", async () => {
    const mockFetch = createMockFetch({
      "/api/db/test-db/stats": {
        ok: true,
        data: { size: 1000, dim: 384, metric: "cosine", strategy: "hnsw" },
      },
    });
    globalThis.fetch = mockFetch;

    const { result } = renderHook(() => useDatabase(), { wrapper });

    act(() => {
      result.current.selectDatabase("test-db");
    });

    expect(result.current.databaseName).toBe("test-db");

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false);
    });

    expect(result.current.stats).toEqual({
      size: 1000,
      dim: 384,
      metric: "cosine",
      strategy: "hnsw",
    });
    expect(result.current.isConnected).toBe(true);
  });

  it("should handle stats fetch error", async () => {
    const mockFetch = createMockFetch({
      "/api/db/bad-db/stats": {
        ok: false,
        status: 404,
        data: { error: { message: "Database not found" } },
      },
    });
    globalThis.fetch = mockFetch;

    const { result } = renderHook(() => useDatabase(), { wrapper });

    act(() => {
      result.current.selectDatabase("bad-db");
    });

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false);
    });

    expect(result.current.error).not.toBeNull();
    expect(result.current.isConnected).toBe(false);
  });

  it("should disconnect and clear state", async () => {
    const mockFetch = createMockFetch({
      "/api/db/test-db/stats": {
        ok: true,
        data: { size: 100, dim: 128, metric: "l2", strategy: "bruteforce" },
      },
    });
    globalThis.fetch = mockFetch;

    const { result } = renderHook(() => useDatabase(), { wrapper });

    act(() => {
      result.current.selectDatabase("test-db");
    });

    await waitFor(() => {
      expect(result.current.isConnected).toBe(true);
    });

    act(() => {
      result.current.disconnect();
    });

    expect(result.current.databaseName).toBeNull();
    expect(result.current.stats).toBeNull();
    expect(result.current.isConnected).toBe(false);
  });

  it("should search vectors", async () => {
    const mockFetch = createMockFetch({
      "/api/db/test-db/stats": {
        ok: true,
        data: { size: 100, dim: 3, metric: "cosine", strategy: "hnsw" },
      },
      "/api/db/test-db/vectors/search": {
        ok: true,
        data: {
          hits: [
            { id: 1, score: 0.95, attrs: { label: "a" } },
            { id: 2, score: 0.85, attrs: { label: "b" } },
          ],
        },
      },
    });
    globalThis.fetch = mockFetch;

    const { result } = renderHook(() => useDatabase(), { wrapper });

    act(() => {
      result.current.selectDatabase("test-db");
    });

    await waitFor(() => {
      expect(result.current.isConnected).toBe(true);
    });

    let hits: unknown[];
    await act(async () => {
      hits = await result.current.search([0.1, 0.2, 0.3], { k: 10 });
    });

    expect(hits!).toHaveLength(2);
    expect(hits![0]).toEqual({ id: 1, score: 0.95, attrs: { label: "a" } });
  });

  it("should throw when searching without database selected", async () => {
    const { result } = renderHook(() => useDatabase(), { wrapper });

    await expect(
      act(async () => {
        await result.current.search([0.1, 0.2], { k: 5 });
      }),
    ).rejects.toThrow("No database selected");
  });

  it("should upsert vector", async () => {
    const mockFetch = createMockFetch({
      "/api/db/test-db/stats": {
        ok: true,
        data: { size: 0, dim: 3, metric: "cosine", strategy: "hnsw" },
      },
      "/api/db/test-db/vectors/1": {
        ok: true,
        data: { ok: true, id: 1 },
      },
    });
    globalThis.fetch = mockFetch;

    const { result } = renderHook(() => useDatabase(), { wrapper });

    act(() => {
      result.current.selectDatabase("test-db");
    });

    await waitFor(() => {
      expect(result.current.isConnected).toBe(true);
    });

    await act(async () => {
      await result.current.upsert(1, {
        vector: [0.1, 0.2, 0.3],
        attrs: { label: "test" },
      });
    });

    expect(mockFetch).toHaveBeenCalledWith(
      "/api/db/test-db/vectors/1",
      expect.objectContaining({ method: "PUT" }),
    );
  });

  it("should delete vector", async () => {
    const mockFetch = createMockFetch({
      "/api/db/test-db/stats": {
        ok: true,
        data: { size: 1, dim: 3, metric: "cosine", strategy: "hnsw" },
      },
      "/api/db/test-db/vectors/1": {
        ok: true,
        data: { ok: true },
      },
    });
    globalThis.fetch = mockFetch;

    const { result } = renderHook(() => useDatabase(), { wrapper });

    act(() => {
      result.current.selectDatabase("test-db");
    });

    await waitFor(() => {
      expect(result.current.isConnected).toBe(true);
    });

    await act(async () => {
      await result.current.deleteById(1);
    });

    expect(mockFetch).toHaveBeenCalledWith(
      "/api/db/test-db/vectors/1",
      expect.objectContaining({ method: "DELETE" }),
    );
  });

  it("should save database", async () => {
    const mockFetch = createMockFetch({
      "/api/db/test-db/stats": {
        ok: true,
        data: { size: 100, dim: 384, metric: "cosine", strategy: "hnsw" },
      },
      "/api/db/test-db/save": {
        ok: true,
        data: { ok: true },
      },
    });
    globalThis.fetch = mockFetch;

    const { result } = renderHook(() => useDatabase(), { wrapper });

    act(() => {
      result.current.selectDatabase("test-db");
    });

    await waitFor(() => {
      expect(result.current.isConnected).toBe(true);
    });

    let saveResult: { ok: boolean };
    await act(async () => {
      saveResult = await result.current.save();
    });

    expect(saveResult!.ok).toBe(true);
  });

  it("should check health", async () => {
    const mockFetch = createMockFetch({
      "/health": {
        ok: true,
        data: { ok: true },
      },
    });
    globalThis.fetch = mockFetch;

    const { result } = renderHook(() => useDatabase(), { wrapper });

    let healthResult: { ok: boolean };
    await act(async () => {
      healthResult = await result.current.health();
    });

    expect(healthResult!.ok).toBe(true);
  });
});
