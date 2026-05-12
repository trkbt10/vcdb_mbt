import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { resolve } from "path";
import { DEFAULT_PORT, DEFAULT_HOST } from "@vcdb/vcdb-features/constants";

const backendUrl = `http://${DEFAULT_HOST === "0.0.0.0" ? "localhost" : DEFAULT_HOST}:${DEFAULT_PORT}`;

export default defineConfig({
  plugins: [react()],
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
  resolve: {
    alias: {
      "@": resolve(__dirname, "src"),
      "@vcdb/api-client": resolve(__dirname, "../api-client/src/index.ts"),
      "@vcdb/data-source": resolve(__dirname, "../data-source/src/index.ts"),
      "@vcdb/db-viewer": resolve(__dirname, "../db-viewer/src/index.ts"),
      "@vcdb/ui-kit/theme": resolve(__dirname, "../ui-kit/src/theme/index.ts"),
      "@vcdb/ui-kit/toast": resolve(__dirname, "../ui-kit/src/toast/index.ts"),
      "@vcdb/ui-kit": resolve(__dirname, "../ui-kit/src/index.ts"),
      "@vcdb/vcdb-features/constants": resolve(__dirname, "../vcdb-features/src/constants.ts"),
      "@vcdb/vcdb-features": resolve(__dirname, "../vcdb-features/src/index.ts"),
    },
  },
  css: {
    modules: {
      localsConvention: "camelCase",
    },
  },
});
