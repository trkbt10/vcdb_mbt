import { chromium } from "playwright";

const dashboardUrl = process.env.DASHBOARD_URL ?? "http://127.0.0.1:4179";
const collectionName = process.env.E2E_COLLECTION_NAME ?? "e2e-dashboard";

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();
page.setDefaultTimeout(5000);
page.on("response", async (response) => {
  const url = response.url();
  if (url.includes("/collections")) {
    try {
      console.log(`[api] ${response.status()} ${url} ${await response.text()}`);
    } catch {
      console.log(`[api] ${response.status()} ${url}`);
    }
  }
});

async function step(name, fn) {
  console.log(`[e2e] ${name}`);
  await fn();
}

try {
  await step("open dashboard", async () => {
    await page.goto(dashboardUrl, { waitUntil: "networkidle" });
  });

  await step("create collection", async () => {
    await page.getByTitle("Create Collection").click();
    await page.getByTestId("create-collection-name").fill(collectionName);
    await page.getByTestId("create-collection-dim").fill("4");
    await page.getByTestId("create-collection-submit").click();
    await page.getByTestId(`collection-item-${collectionName}`).waitFor();
  });

  await step("select collection", async () => {
    await page.getByTestId(`collection-item-${collectionName}`).click();
  });

  await step("add row", async () => {
    await page.getByRole("button", { name: "Add Row" }).click();
    await page.getByTestId("add-row-id").fill("1");
    await page.getByTestId("add-row-init-vector").click();
    await page.getByRole("button", { name: "Edit" }).click();
    await page.locator("textarea").fill("1, 0, 0, 0");
    await page.getByRole("button", { name: "Save" }).first().click();
    await page.getByRole("button", { name: "Add Row" }).last().click();
    await page.getByText("Row added successfully").waitFor();
  });

  await step("search row", async () => {
    await page.getByTestId("search-input").fill("1, 0, 0, 0");
    await page.getByTestId("search-input").press("Enter");
    await page.locator('[data-row-id="1"]').waitFor();
  });

  await step("open stats", async () => {
    await page.getByRole("tab", { name: "Stats" }).click();
    await page.getByText("Collection Statistics").waitFor();
  });
} finally {
  await browser.close();
}
