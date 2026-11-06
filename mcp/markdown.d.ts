// Markdown files are bundled as text by scripts/build_theme_mcp.mjs.
declare module '*.md' {
  const text: string;
  export default text;
}
