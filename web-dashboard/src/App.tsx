import { ThemeProvider } from "@/contexts/ThemeContext";
import { DatabaseProvider } from "@/contexts/DatabaseContext";
import { ToastProvider } from "@/contexts/ToastContext";
import { RegistryProvider } from "@/features/registry/hooks/useRegistry";
import { Shell } from "@/components/layout/Shell";

export function App() {
  return (
    <ThemeProvider>
      <DatabaseProvider>
        <ToastProvider>
          <RegistryProvider>
            <Shell />
          </RegistryProvider>
        </ToastProvider>
      </DatabaseProvider>
    </ThemeProvider>
  );
}
