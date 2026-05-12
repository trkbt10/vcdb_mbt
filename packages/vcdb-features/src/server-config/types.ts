/**
 * @file Shape of the dashboard server's runtime configuration as exposed by
 * `/api/config/dashboard`. The dashboard server (currently the vcdb npm
 * package's bin/vcdb-server.js) returns and accepts patches of this shape.
 */

export interface DashboardConfig {
  /** Bind host for the gateway/dashboard process. */
  readonly host: string;
  /** Bind port for the gateway/dashboard process. */
  readonly port: number;
  /** Filesystem root the gateway uses for collection data. */
  readonly baseDir: string;
}
