import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { readdirSync } from 'node:fs';
import { join } from 'node:path';

function pages(directory: string, extensions = ['.tsx']): string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) return pages(path, extensions);
    return extensions.some((extension) => path.endsWith(extension)) ? [path] : [];
  });
}

// Wellout pages link stylesheets and islands directly, so each is its own entry.
const views = [
  ...pages('resources/js/islands', ['.ts', '.tsx']),
  ...pages('resources/css', ['.css']),
];

export default defineConfig({
  plugins: [react()],
  base: '/build/',
  publicDir: 'public',
  build: {
    outDir: 'public/build',
    emptyOutDir: true,
    copyPublicDir: false,
    manifest: true,
    cssCodeSplit: true,
    rollupOptions: {
      input: views,
      // Islands are loaded with import() and must keep their mount export.
      preserveEntrySignatures: 'exports-only',
    },
  },
  server: { host: '127.0.0.1', port: 5173, strictPort: true },
});
