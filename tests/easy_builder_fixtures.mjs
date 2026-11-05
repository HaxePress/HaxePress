import { readFile } from 'node:fs/promises';
import ts from 'typescript';

async function moduleCode(name) {
  const source = await readFile(
    new URL('../resources/js/themes/builder/' + name + '.ts', import.meta.url),
    'utf8',
  );
  return ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 },
  }).outputText;
}
function moduleUrl(code) {
  return 'data:text/javascript;base64,' + Buffer.from(code).toString('base64');
}
const types = moduleUrl(await moduleCode('types'));
const presets = moduleUrl(
  (await moduleCode('presets')).replace(/from ['"]\.\/types['"]/g, 'from ' + JSON.stringify(types)),
);
const friendly = moduleUrl(
  (await moduleCode('friendly-presets'))
    .replace(/from ['"]\.\/types['"]/g, 'from ' + JSON.stringify(types))
    .replace(/from ['"]\.\/presets['"]/g, 'from ' + JSON.stringify(presets)),
);
const { friendlyDocument, starterChoices, paletteChoices, sectionChoices, friendlySection } =
  await import(friendly);
let input = '';
for await (const chunk of process.stdin) input += chunk;
const base = JSON.parse(input);
const documents = Object.fromEntries(
  starterChoices.map((starter, index) => [
    starter.id,
    friendlyDocument(base, starter.id, paletteChoices[index].value, index % 2 ? 'serif' : 'sans'),
  ]),
);
const sections = sectionChoices.map((choice) => friendlySection(choice.id));
process.stdout.write(JSON.stringify({ documents, sections }));
