import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tsconfigPaths from "vite-tsconfig-paths";
import { DEFAULT_PORT, DEFAULT_HOST } from "@vcdb/vcdb-features/constants";

const backendUrl = `http://${DEFAULT_HOST === "0.0.0.0" ? "localhost" : DEFAULT_HOST}:${DEFAULT_PORT}`;

// All `@vcdb/*` and `vcdb/*` aliases come from this package's tsconfig.json
// via vite-tsconfig-paths — keep workspace resolution declared in one place.
export default defineConfig({
  plugins: [react(), tsconfigPaths()],
  server: {
    port: 5179,
    proxy: {
      "/collections": {
        target: backendUrl,
        changeOrigin: true,
      },
      "/healthz": {
        target: backendUrl,
        changeOrigin: true,
      },
    },
  },
  css: {
    modules: {
      localsConvention: "camelCase",
    },
  },
});
