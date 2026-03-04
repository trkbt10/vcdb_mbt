/**
 * Minimal Bun types for the vcdb server.
 * Extends globalThis to include Bun when running in Bun runtime.
 */

declare global {
  interface BunServeOptions {
    port: number;
    hostname?: string;
    fetch(req: Request): Promise<Response> | Response;
  }

  interface BunServer {
    stop(): void;
    port: number;
    hostname: string;
  }

  interface BunRuntime {
    serve(options: BunServeOptions): BunServer;
  }

  // eslint-disable-next-line no-var
  var Bun: BunRuntime | undefined;
}

export {};
