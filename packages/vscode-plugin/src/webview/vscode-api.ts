import type {
  ExtensionToWebviewMessage,
  WebviewToExtensionMessage,
} from "../shared/protocol.ts";

interface VsCodeApi<TPost> {
  postMessage(message: TPost): void;
  getState<T>(): T | undefined;
  setState<T>(state: T): T;
}

declare const acquireVsCodeApi: <TPost = WebviewToExtensionMessage>() => VsCodeApi<TPost>;

let cached: VsCodeApi<WebviewToExtensionMessage> | null = null;

export function getVsCodeApi(): VsCodeApi<WebviewToExtensionMessage> {
  if (!cached) {
    cached = acquireVsCodeApi<WebviewToExtensionMessage>();
  }
  return cached;
}

export type { ExtensionToWebviewMessage, WebviewToExtensionMessage };
