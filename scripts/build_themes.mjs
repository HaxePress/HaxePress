import postcss from 'postcss';
import { cp, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const source = join(root, 'examples/themes');
const output = join(root, 'Export/themes');

function scopedStyles(css) {
  const sheet = postcss.parse(css);
  sheet.walkRules((rule) => {
    let parent = rule.parent;
    while (parent) {
      if (parent.type === 'atrule' && parent.name.endsWith('keyframes')) return;
      parent = parent.parent;
    }
    rule.selectors = postcss.list.comma(rule.selector).map((selector) => {
      if (selector.startsWith('.cms-site')) return selector;
      if ([':root', 'html', 'body'].includes(selector)) return '.cms-site';
      return `.cms-site ${selector}`;
    });
  });
  return sheet.toString();
}

for (const entry of await readdir(source, { withFileTypes: true })) {
  if (!entry.isDirectory()) continue;
  const directory = join(source, entry.name);
  const manifest = JSON.parse(await readFile(join(directory, 'cms-package.json'), 'utf8'));
  const destination = join(output, entry.name);
  // Start from an empty folder, so files a theme no longer has never reach its ZIP.
  await rm(destination, { recursive: true, force: true });
  await mkdir(destination, { recursive: true });
  await cp(directory, destination, { recursive: true });
  if (manifest.assets.views) {
    // Gallery and Notebook share the Fieldnotes templates and differ in style only.
    if (entry.name !== 'fieldnotes') {
      await cp(join(source, 'fieldnotes/views'), join(destination, manifest.assets.views), {
        recursive: true,
      });
    }
    let css = await readFile(join(source, 'fieldnotes/public/theme.css'), 'utf8');
    if (entry.name !== 'fieldnotes') {
      css += `\n${await readFile(join(directory, 'public/theme.css'), 'utf8')}`;
      for (const folder of ['fonts', 'images']) {
        await cp(join(source, 'fieldnotes/public', folder), join(destination, 'public', folder), {
          recursive: true,
        });
      }
    }
    await writeFile(join(destination, 'public/theme.css'), scopedStyles(css));
  }
}
console.log('Built packaged themes. The default theme is part of the application.');
