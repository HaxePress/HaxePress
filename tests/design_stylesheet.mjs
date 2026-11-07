// Prints the editor preview's stylesheet for the design document on stdin, so integration tests
// can compare it with the stylesheet the server publishes.
import { readFile } from 'node:fs/promises';
import ts from 'typescript';

async function moduleCode(name) {
  const source = await readFile(
    new URL(`../resources/js/themes/builder/${name}.ts`, import.meta.url),
    'utf8',
  );
  return ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 },
  }).outputText;
}
function moduleUrl(code) {
  return `data:text/javascript;base64,${Buffer.from(code).toString('base64')}`;
}
const types = moduleUrl(await moduleCode('types'));
const styles = moduleUrl(
  (await moduleCode('styles')).replace(/from ['"]\.\/types['"]/g, `from ${JSON.stringify(types)}`),
);
const { designStyles } = await import(styles);
let input = '';
for await (const chunk of process.stdin) input += chunk;
process.stdout.write(designStyles(JSON.parse(input)));
