export const profiles = {
  web: 'Web',
  chatgpt: 'ChatGPT / Codex',
  claude: 'Claude',
  gemini: 'Gemini CLI',
  codex: 'Codex',
  cursor: 'Cursor',
  copilot: 'GitHub Copilot',
  grok: 'Grok API',
  http: 'Other MCP clients',
} as const;

export type McpProfile = keyof typeof profiles;
export type RemoteProfile = Exclude<McpProfile, 'web'>;

export const clientChoices = [
  'web',
  'chatgpt',
  'claude',
  'gemini',
  'cursor',
  'copilot',
  'grok',
  'http',
] as const satisfies readonly McpProfile[];

export type ClientChoice = (typeof clientChoices)[number];

export interface McpConnection {
  id: string;
  profile: RemoteProfile;
  url: string;
  token: string;
  expires: number;
}

export const browserPrompt = [
  'You are operating the HaxePress administration panel in a signed-in browser.',
  'Use the page JavaScript MCP API at window.haxePress.adminMcp. Start with getContext() and listTools(), then call callTool(name, arguments).',
  'If your extension supports WebMCP, discover the haxepress_admin_* tools instead. A theme editor also exposes window.haxePress.themeDesigner for tools scoped to the current theme.',
  'For images, stage the original file, inspect the echoed image and verify its SHA-256 and measured dimensions. Use the verified media ID for content, and the verified theme asset URL for theme designs.',
  'Read the latest content or theme version before making changes.',
].join('\n\n');

export const setupInstructions: Record<RemoteProfile, string> = {
  chatgpt:
    'Add this entry to ~/.codex/config.toml and restart your client. ChatGPT desktop and Codex share this configuration on the same host.',
  claude:
    'Run the command in Claude Code. For a Claude web connector, paste the server URL and add the Authorization header under Request headers. Claude web requires a reachable HTTPS deployment.',
  gemini: 'Run this command to add HaxePress to your personal Gemini CLI configuration.',
  codex: 'Run these commands in the shell you use to launch Codex, then restart the client.',
  cursor: 'Merge this entry into ~/.cursor/mcp.json, then restart Cursor.',
  copilot:
    'Merge this entry into your Copilot user mcp-config.json and reload VS Code. The default path is ~/.copilot/mcp-config.json.',
  grok: 'Add this tool to the tools array in an xAI Responses API request. Use a publicly reachable HTTPS MCP URL.',
  http: 'Configure a Streamable HTTP MCP server with this URL and Authorization header.',
};

export function connectionDetails(
  connection: McpConnection,
  profile: RemoteProfile = connection.profile,
): string {
  const { id, url, token } = connection;
  const name = `haxepress-${id.slice(0, 8)}`;
  const authorization = `Bearer ${token}`;
  const headers = { Authorization: authorization };
  switch (profile) {
    case 'chatgpt':
      return [
        `[mcp_servers."${name}"]`,
        `url = "${url}"`,
        `http_headers = { Authorization = "${authorization}" }`,
      ].join('\n');
    case 'claude':
      return [
        `claude mcp add --transport http ${name} '${url}' \\`,
        `  --header "Authorization: ${authorization}"`,
      ].join('\n');
    case 'gemini':
      return [
        'gemini mcp add --scope user --transport http \\',
        `  --header "Authorization: ${authorization}" ${name} '${url}'`,
      ].join('\n');
    case 'codex': {
      const variable = `HAXEPRESS_MCP_${id
        .slice(0, 8)
        .replace(/[^a-z0-9]/gi, '_')
        .toUpperCase()}`;
      return [
        `export ${variable}='${token}'`,
        `codex mcp add ${name} --url '${url}' --bearer-token-env-var ${variable}`,
      ].join('\n');
    }
    case 'cursor':
      return JSON.stringify({ mcpServers: { [name]: { url, headers } } }, null, 2);
    case 'copilot':
      return JSON.stringify({ mcpServers: { [name]: { type: 'http', url, headers } } }, null, 2);
    case 'grok':
      return JSON.stringify({ type: 'mcp', server_url: url, server_label: name, headers }, null, 2);
    case 'http':
      return JSON.stringify({ url, type: 'http', headers }, null, 2);
  }
}
