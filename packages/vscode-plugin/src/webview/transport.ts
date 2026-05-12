import type { Transport } from "@vcdb/webview-bridge";
import { getVsCodeApi } from "./vscode-api.ts";

/**
 * Adapt the vscode webview's postMessage API (one-way `postMessage` +
 * `window.addEventListener("message")`) to the generic `Transport`
 * interface consumed by @vcdb/webview-bridge.
 */
export function createVscodeWebviewTransport(): Transport {
  const api = getVsCodeApi();
  return {
    postMessage: (message) => {
      // The vscode types narrow this, but for the bridge we accept any payload.
      api.postMessage(message as never);
    },
    onMessage: (handler) => {
      const listener = (event: MessageEvent<unknown>) => handler(event.data);
      window.addEventListener("message", listener);
      return () => window.removeEventListener("message", listener);
    },
  };
}
