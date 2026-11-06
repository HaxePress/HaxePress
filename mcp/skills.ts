// Serves the theme design skill to MCP clients. Hosts that support the skills
// extension (SEP-2640) discover it with skills/list and read its files as
// skill:// resources; every client can also reach it through a prompt and a
// read-only tool.
import { ProtocolError, ProtocolErrorCode, type McpServer } from '@modelcontextprotocol/server';
import { createHash } from 'node:crypto';
import * as z from 'zod/v4';
import skill from './skills/haxepress-theme-design/SKILL.md';
import documentModel from './skills/haxepress-theme-design/references/document-model.md';
import editOperations from './skills/haxepress-theme-design/references/edit-operations.md';
import renderedMarkup from './skills/haxepress-theme-design/references/rendered-markup.md';
import visualReview from './skills/haxepress-theme-design/references/visual-review.md';

export const SKILLS_EXTENSION = 'io.modelcontextprotocol/skills';
const NAME = 'haxepress-theme-design';
const ROOT = `skill://${NAME}`;
export const THEME_SKILL_URI = `${ROOT}/SKILL.md`;

const sources: Record<string, string> = {
  'SKILL.md': skill,
  'references/document-model.md': documentModel,
  'references/edit-operations.md': editOperations,
  'references/rendered-markup.md': renderedMarkup,
  'references/visual-review.md': visualReview,
};
export type SkillFile = keyof typeof sources;
export const skillFiles = Object.keys(sources) as SkillFile[];

type Frontmatter = Record<string, string | Record<string, string>>;

/**
 * Reads the skill's YAML frontmatter. It accepts the subset the skill uses:
 * plain or double-quoted scalars and one level of nested mappings. Anything
 * else stops the server instead of publishing frontmatter that differs from
 * the file.
 */
export function frontmatter(markdown: string): Frontmatter {
  const block = /^---\n([\s\S]*?)\n---\n/.exec(markdown);
  if (!block) throw new Error('The skill needs YAML frontmatter.');
  const scalar = (value: string) => {
    if (value.startsWith('"')) {
      if (!/^"(?:[^"\\]|\\.)*"$/.test(value)) throw new Error(`Unsupported value: ${value}`);
      return JSON.parse(value) as string;
    }
    // Prettier writes YAML strings in single quotes, where '' is a quote.
    if (value.startsWith("'")) {
      if (!/^'(?:[^']|'')*'$/.test(value)) throw new Error(`Unsupported value: ${value}`);
      return value.slice(1, -1).replaceAll("''", "'");
    }
    if (/^['&*!|>%@`{[]|: | #/.test(value)) throw new Error(`Unsupported value: ${value}`);
    return value;
  };
  const result: Frontmatter = {};
  let nested: Record<string, string> | null = null;
  for (const line of block[1].split('\n')) {
    const child = /^ {2}([a-z][a-z0-9-]*): (.+)$/.exec(line);
    if (child && nested) {
      nested[child[1]] = scalar(child[2]);
      continue;
    }
    const parent = /^([a-z][a-z0-9-]*):(?: (.+))?$/.exec(line);
    if (!parent) throw new Error(`Unsupported frontmatter line: ${line}`);
    if (parent[2] === undefined) {
      nested = {};
      result[parent[1]] = nested;
    } else {
      nested = null;
      result[parent[1]] = scalar(parent[2]);
    }
  }
  if (result.name !== NAME || typeof result.description !== 'string')
    throw new Error('The skill frontmatter needs its name and a description.');
  return result;
}

const metadata = frontmatter(skill);
const description = metadata.description as string;
const entry = {
  uri: THEME_SKILL_URI,
  frontmatter: metadata,
  resources: skillFiles.map((path) => {
    const bytes = Buffer.from(sources[path], 'utf8');
    return {
      uri: `${ROOT}/${path}`,
      digest: `sha256:${createHash('sha256').update(bytes).digest('hex')}`,
      size: bytes.length,
    };
  }),
};

/** The instructions line that points every client at the skill. */
export const skillPointer = `Before designing, restyling or reviewing a theme, read the theme design skill: the resource ${THEME_SKILL_URI}, or the get_theme_design_skill tool when resources are unavailable.`;

export function registerThemeSkill(server: McpServer) {
  server.server.registerCapabilities({ resources: {}, extensions: { [SKILLS_EXTENSION]: {} } });
  server.server.setRequestHandler(
    'skills/list',
    { params: z.looseObject({ cursor: z.string().optional() }) },
    async () => ({ resultType: 'complete', skills: [entry] }),
  );
  server.server.setRequestHandler(
    'skills/get',
    { params: z.looseObject({ uri: z.string() }) },
    async ({ uri }) => {
      if (uri !== THEME_SKILL_URI)
        throw new ProtocolError(ProtocolErrorCode.InvalidParams, 'Unknown skill');
      return { resultType: 'complete', skill: entry };
    },
  );

  for (const path of skillFiles) {
    const uri = `${ROOT}/${path}`;
    const main = path === 'SKILL.md';
    server.registerResource(
      main ? NAME : `${NAME}/${path}`,
      uri,
      {
        mimeType: 'text/markdown',
        description: main ? description : `Reference for the ${NAME} skill.`,
      },
      async () => ({ contents: [{ uri, mimeType: 'text/markdown', text: sources[path] }] }),
    );
  }

  server.registerTool(
    'get_theme_design_skill',
    {
      description:
        'Read the theme design skill: the workflow, design rules and review checklist for creating or restyling a HaxePress theme. Read SKILL.md first, then a reference file when it points you there.',
      inputSchema: z.object({
        file: z
          .enum(skillFiles as [SkillFile, ...SkillFile[]])
          .default('SKILL.md')
          .describe('A file of the skill, relative to its folder.'),
      }),
      annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false },
    },
    async ({ file }) => ({ content: [{ type: 'text', text: sources[file] }] }),
  );

  server.registerPrompt(
    'design_theme',
    {
      title: 'Design a theme',
      description: 'Create or restyle a HaxePress theme with the theme design skill.',
      argsSchema: z.object({
        brief: z
          .string()
          .max(4000)
          .describe('What the site is about and how it should look and feel.'),
      }),
    },
    ({ brief }) => ({
      messages: [
        {
          role: 'user',
          content: {
            type: 'text',
            text: `${skill}\n\n---\n\nFollow the skill above. Its reference files are available as ${ROOT}/references/… resources or through get_theme_design_skill.\n\nThe brief:\n\n${brief}`,
          },
        },
      ],
    }),
  );
}
