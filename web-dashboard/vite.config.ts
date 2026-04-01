import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { resolve } from "path";
import { DEFAULT_PORT, DEFAULT_HOST } from "./src/constants";

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
    },
  },
  css: {
    modules: {
      localsConvention: "camelCase",
    },
  },
});
