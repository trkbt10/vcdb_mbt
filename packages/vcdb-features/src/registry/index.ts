// RegistryPage.tsx depends on react-router but the package isn't installed —
// the route was never wired up in App.tsx. Re-export once the routing layer
// lands. For now consume registry pieces via the components barrel.
export { ConnectionManager } from "./components/index.ts";
export type { DatabaseInfo } from "./components/index.ts";
