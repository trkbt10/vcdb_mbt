import { ThemeProvider } from "@vcdb/ui-kit/theme";
import { ToastProvider } from "@vcdb/ui-kit/toast";
import {
  DatabaseProvider,
  ExplorerPage,
  RegistryProvider,
} from "@vcdb/vcdb-features";
import { Shell } from "@/components/layout/Shell";

export function App() {
  return (
    <ThemeProvider>
      <DatabaseProvider>
        <ToastProvider>
          <RegistryProvider>
            <Shell renderContent={(db) => (db ? <ExplorerPage /> : null)} />
          </RegistryProvider>
        </ToastProvider>
      </DatabaseProvider>
    </ThemeProvider>
  );
}
