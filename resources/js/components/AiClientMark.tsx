import type { ClientChoice } from '../ai/admin-connection-prompt';
import claude from '../ai/client-marks/claude-color.svg';
import cursor from '../ai/client-marks/cursor.svg';
import gemini from '../ai/client-marks/gemini-color.svg';
import copilot from '../ai/client-marks/githubcopilot.svg';
import grok from '../ai/client-marks/grok.svg';
import openai from '../ai/client-marks/openai.svg';
import Icon from './Icon';

const brandMarks: Partial<Record<ClientChoice, string>> = {
  chatgpt: openai,
  claude,
  gemini,
  cursor,
  copilot,
  grok,
};

export default function AiClientMark({ client }: { client: ClientChoice }) {
  const mark = brandMarks[client];
  return (
    <span className="admin-ai-client-mark" aria-hidden="true">
      {mark ? <img src={mark} alt="" /> : <Icon name={client === 'web' ? 'compass' : 'code'} />}
    </span>
  );
}
