declare module "*.module.css" {
  const classes: { readonly [key: string]: string };
  export default classes;
}

// Plain CSS side-effect imports (global styles bundled by bun).
declare module "*.css";
