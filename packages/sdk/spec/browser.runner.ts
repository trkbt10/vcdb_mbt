#!/usr/bin/env npx tsx
/**
 * @file Browser storage spec runner using Playwright
 *
 * Tests: IndexedDB, localStorage, OPFS, Cache API
 *
 * Install playwright: npx playwright install chromium
 */
import { chromium } from "playwright";
import * as http from "node:http";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

async function main() {
  console.log("StorageAdapter Spec Runner (Browser)\n");
  console.log("=====================================\n");

  const htmlPath = path.join(__dirname, "browser.html");

  if (!fs.existsSync(htmlPath)) {
    console.error("browser.html not found");
    process.exit(1);
  }

  // Start simple HTTP server (required for OPFS, Cache API)
  const html = fs.readFileSync(htmlPath, "utf-8");
  const server = http.createServer((req, res) => {
    res.writeHead(200, { "Content-Type": "text/html" });
    res.end(html);
  });

  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = (server.address() as { port: number }).port;
  const url = `http://127.0.0.1:${port}/`;

  try {
    const browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();

    // Collect console output
    page.on("console", (msg) => {
      const text = msg.text();
      if (text.includes("✓")) {
        console.log(`\x1b[32m${text}\x1b[0m`);
      } else if (text.includes("✗") || text.includes("error")) {
        console.log(`\x1b[31m${text}\x1b[0m`);
      } else if (text.includes("===")) {
        console.log(`\x1b[36m${text}\x1b[0m`);
      } else if (text.includes("⚠")) {
        console.log(`\x1b[33m${text}\x1b[0m`);
      } else {
        console.log(text);
      }
    });

    page.on("pageerror", (err) => {
      console.log(`\x1b[31mPage error: ${err}\x1b[0m`);
    });

    // Navigate to test page
    await page.goto(url);

    // Wait for tests to complete
    await page.waitForFunction(() => (window as any).__specResult !== undefined, {
      timeout: 60000,
    });

    // Get results
    const result = await page.evaluate(() => (window as any).__specResult);

    await browser.close();

    console.log("\n=====================================");

    if (result.failed > 0) {
      console.log(`\n${result.failed} test(s) failed\n`);
      process.exit(1);
    } else {
      console.log("\nAll browser specs passed!\n");
    }
  } finally {
    server.close();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
