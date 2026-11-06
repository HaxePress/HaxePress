import type { CSSProperties } from 'react';
import type { StarterChoice, FriendlySection } from './friendly-presets';

export default function FriendlyPreview({
  kind,
  accent = '#405bcc',
}: {
  kind: StarterChoice | FriendlySection;
  accent?: string;
}) {
  return (
    <span
      className={`easy-mini easy-mini-${kind}`}
      style={{ '--mini-accent': accent } as CSSProperties}
      aria-hidden="true"
    >
      <span className="easy-mini-nav">
        <i />
        <b />
        <b />
        <b />
      </span>
      {['portfolio', 'split'].includes(kind) && (
        <span className="easy-mini-photo">
          <svg viewBox="0 0 60 40">
            <path
              d="M4 36 22 15l13 14 9-9 13 16M40 8h.1"
              fill="none"
              stroke="currentColor"
              strokeWidth="3"
            />
          </svg>
        </span>
      )}
      <span className="easy-mini-copy">
        <strong />
        <em />
        <em />
        <small />
      </span>
      {['business', 'highlights', 'journal', 'content', 'portfolio'].includes(kind) && (
        <span className="easy-mini-cards">
          <i />
          <i />
          <i />
        </span>
      )}
      {kind === 'questions' && (
        <span className="easy-mini-question-lines">
          <i />
          <i />
          <i />
        </span>
      )}
      {kind === 'blank' && <span className="easy-mini-blank-mark">+</span>}
    </span>
  );
}
