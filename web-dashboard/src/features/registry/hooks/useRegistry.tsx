import { createContext, useContext, type ReactNode } from "react";
import { useRegistryApi } from "./useRegistryApi";

type RegistryContextValue = ReturnType<typeof useRegistryApi>;

const RegistryContext = createContext<RegistryContextValue | null>(null);

export function RegistryProvider({ children }: { children: ReactNode }) {
  const value = useRegistryApi();
  return <RegistryContext.Provider value={value}>{children}</RegistryContext.Provider>;
}

export function useRegistry(): RegistryContextValue {
  const context = useContext(RegistryContext);
  if (!context) {
    throw new Error("useRegistry must be used within RegistryProvider");
  }
  return context;
}
