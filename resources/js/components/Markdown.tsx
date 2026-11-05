import { memo } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import rehypeSlug from 'rehype-slug';

export function allowedImage(url: string) {
  return /^\/media\/[A-Za-z0-9_-]{32}\.(jpg|png|webp|gif)$/.test(url);
}

function Markdown({ content }: { content: string }) {
  return (
    <ReactMarkdown
      remarkPlugins={[remarkGfm]}
      rehypePlugins={[[rehypeSlug, { prefix: 'content-' }]]}
      components={{
        h1: ({ children, id }) => <h2 id={id}>{children}</h2>,
        img: ({ src, alt }) =>
          typeof src === 'string' && allowedImage(src) ? (
            <img src={src} alt={alt || ''} loading="lazy" />
          ) : null,
        p: ({ node, children }) => {
          const hasImage = node?.children.some(
            (child) => child.type === 'element' && child.tagName === 'img',
          );
          const onlyImages = node?.children.every(
            (child) =>
              (child.type === 'element' && child.tagName === 'img') ||
              (child.type === 'text' && child.value.trim() === ''),
          );
          return hasImage && onlyImages ? (
            <figure className="content-inline-image">{children}</figure>
          ) : (
            <p>{children}</p>
          );
        },
        a: ({ href, children }) => (
          <a
            href={href}
            {...(/^https?:\/\//i.test(href || '') && {
              target: '_blank',
              rel: 'noopener noreferrer',
            })}
          >
            {children}
          </a>
        ),
        table: ({ children }) => (
          <div className="markdown-table">
            <table>{children}</table>
          </div>
        ),
      }}
    >
      {content}
    </ReactMarkdown>
  );
}

export default memo(Markdown);
