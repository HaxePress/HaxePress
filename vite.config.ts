import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { readdirSync } from 'node:fs';
import { join } from 'node:path';

function pages(directory: string): string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? pages(path) : path.endsWith('.tsx') ? [path] : [];
  });
}

export default defineConfig(({ isSsrBuild }) => ({
  plugins: [react()],
  base: '/build/',
  publicDir: 'public',
  build: {
    outDir: isSsrBuild ? 'bootstrap/ssr' : 'public/build',
    emptyOutDir: true,
    copyPublicDir: false,
    manifest: !isSsrBuild,
    cssCodeSplit: true,
    rollupOptions: isSsrBuild
      ? {}
      : { input: ['resources/js/app.tsx', ...pages('resources/js/pages')] },
  },
  server: { host: '127.0.0.1', port: 5173, strictPort: true },
}));
