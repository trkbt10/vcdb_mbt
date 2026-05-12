import { ThemeProvider } from "@vcdb/ui-kit/theme";
import { DatabaseProvider } from "@/contexts/DatabaseContext";
import { ToastProvider } from "@vcdb/ui-kit/toast";
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
