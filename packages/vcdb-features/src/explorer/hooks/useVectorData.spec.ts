/**
 * @file Tests for useVectorData hook
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, act, waitFor } from "@testing-library/react";
import { useVectorData, type UseVectorDataOptions, type ListVectorsResult } from "./useVectorData";

describe("useVectorData", () => {
  const mockListVectors = vi.fn<
    (options?: { limit?: number; offset?: number }) => Promise<ListVectorsResult>
  >();

  const defaultOptions: UseVectorDataOptions = {
    listVectors: mockListVectors,
    isConnected: true,
    databaseName: "test-db",
    pageSize: 10,
  };

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("should return initial state when not connected", () => {
    const { result } = renderHook(() =>
      useVectorData({
        ...defaultOptions,
        isConnected: false,
      }),
    );

    expect(result.current.rows).toEqual([]);
    expect(result.current.loading).toBe(false);
    expect(result.current.error).toBeNull();
    expect(result.current.total).toBe(0);
  });

  it("should return initial state when no database is selected", () => {
    const { result } = renderHook(() =>
      useVectorData({
        ...defaultOptions,
        databaseName: null,
      }),
    );

    expect(result.current.rows).toEqual([]);
    expect(result.current.loading).toBe(false);
    expect(result.current.error).toBeNull();
    expect(result.current.total).toBe(0);
  });

  it("should load data when connected and database is selected", async () => {
    const mockData: ListVectorsResult = {
      rows: [
        { id: 1, attrs: { title: "Test 1" } },
        { id: 2, attrs: { title: "Test 2" } },
      ],
      total: 2,
      offset: 0,
      limit: 10,
    };
    mockListVectors.mockResolvedValueOnce(mockData);

    const { result } = renderHook(() => useVectorData(defaultOptions));

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(mockListVectors).toHaveBeenCalledWith({ limit: 10 });
    expect(result.current.rows).toEqual([
      { id: 1, attrs: { title: "Test 1" } },
      { id: 2, attrs: { title: "Test 2" } },
    ]);
    expect(result.current.total).toBe(2);
    expect(result.current.error).toBeNull();
  });

  it("should handle load error", async () => {
    mockListVectors.mockRejectedValueOnce(new Error("Network error"));

    const { result } = renderHook(() => useVectorData(defaultOptions));

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(result.current.error).toBe("Network error");
    expect(result.current.rows).toEqual([]);
    expect(result.current.total).toBe(0);
  });

  it("should handle non-Error rejection", async () => {
    mockListVectors.mockRejectedValueOnce("String error");

    const { result } = renderHook(() => useVectorData(defaultOptions));

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(result.current.error).toBe("Failed to load data");
  });

  it("should reload data when reload is called", async () => {
    const mockData1: ListVectorsResult = {
      rows: [{ id: 1, attrs: null }],
      total: 1,
      offset: 0,
      limit: 10,
    };
    const mockData2: ListVectorsResult = {
      rows: [
        { id: 1, attrs: null },
        { id: 2, attrs: { new: true } },
      ],
      total: 2,
      offset: 0,
      limit: 10,
    };
    mockListVectors.mockResolvedValueOnce(mockData1).mockResolvedValueOnce(mockData2);

    const { result } = renderHook(() => useVectorData(defaultOptions));

    await waitFor(() => {
      expect(result.current.rows).toHaveLength(1);
    });

    await act(async () => {
      await result.current.reload();
    });

    expect(result.current.rows).toHaveLength(2);
    expect(result.current.total).toBe(2);
  });

  it("should reset state when database changes", async () => {
    const mockData: ListVectorsResult = {
      rows: [{ id: 1, attrs: { title: "Test" } }],
      total: 1,
      offset: 0,
      limit: 10,
    };
    mockListVectors.mockResolvedValue(mockData);

    const { result, rerender } = renderHook(
      (props: UseVectorDataOptions) => useVectorData(props),
      { initialProps: defaultOptions },
    );

    await waitFor(() => {
      expect(result.current.rows).toHaveLength(1);
    });

    // Change database
    rerender({
      ...defaultOptions,
      databaseName: "new-db",
    });

    // State should be reset immediately
    expect(result.current.rows).toEqual([]);
    expect(result.current.total).toBe(0);
    expect(result.current.error).toBeNull();

    // Wait for new data to load
    await waitFor(() => {
      expect(result.current.rows).toHaveLength(1);
    });
  });

  it("should allow manual row updates via setRows", async () => {
    const mockData: ListVectorsResult = {
      rows: [{ id: 1, attrs: null }],
      total: 1,
      offset: 0,
      limit: 10,
    };
    mockListVectors.mockResolvedValueOnce(mockData);

    const { result } = renderHook(() => useVectorData(defaultOptions));

    await waitFor(() => {
      expect(result.current.rows).toHaveLength(1);
    });

    act(() => {
      result.current.setRows([
        { id: 1, score: 0.9, attrs: { search: true } },
        { id: 2, score: 0.8, attrs: { search: true } },
      ]);
    });

    expect(result.current.rows).toHaveLength(2);
    expect(result.current.rows[0].score).toBe(0.9);
  });

  it("should not reload if already loaded initial data", async () => {
    const mockData: ListVectorsResult = {
      rows: [{ id: 1, attrs: null }],
      total: 1,
      offset: 0,
      limit: 10,
    };
    mockListVectors.mockResolvedValue(mockData);

    const { result, rerender } = renderHook(
      (props: UseVectorDataOptions) => useVectorData(props),
      { initialProps: defaultOptions },
    );

    await waitFor(() => {
      expect(result.current.rows).toHaveLength(1);
    });

    // Rerender with same props
    rerender(defaultOptions);

    // Should not trigger another load
    expect(mockListVectors).toHaveBeenCalledTimes(1);
  });

  it("should use default pageSize of 100", async () => {
    const mockData: ListVectorsResult = {
      rows: [],
      total: 0,
      offset: 0,
      limit: 100,
    };
    mockListVectors.mockResolvedValueOnce(mockData);

    renderHook(() =>
      useVectorData({
        listVectors: mockListVectors,
        isConnected: true,
        databaseName: "test-db",
      }),
    );

    await waitFor(() => {
      expect(mockListVectors).toHaveBeenCalledWith({ limit: 100 });
    });
  });
});
