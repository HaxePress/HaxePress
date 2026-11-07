import { usePage } from '../../page';
import {
  createElement,
  Fragment,
  useEffect,
  useState,
  type CSSProperties,
  type DragEvent,
  type MouseEvent,
  type ReactNode,
  type HTMLAttributes,
  type KeyboardEvent,
} from 'react';
import useInlineText from './useInlineText';
import { editableText } from './friendly-presets';
import DesignOverlay from './DesignOverlay';
import PageHead from '../../components/PageHead';
import Markdown from '../../components/Markdown';
import FieldValues from '../../components/FieldValues';
import Pagination from '../../components/Pagination';
import ContentFilters from '../../components/ContentFilters';
import PublicExtensions, { ExtensionSlot } from '../../components/PublicExtensions';
import SiteNavigation from '../../components/SiteNavigation';
import { SiteLink } from '../navigation';
import { useTranslation } from '../../i18n';
import { defaultSite, type ContentItem, type PageLinks, type SharedProps } from '../../types';
import type { PublicCollection } from '../../content';
import { boundText, isVisible, linkValue, imageValue, type BindingContext } from './bindings';
import { classNames, designStyles } from './styles';
import {
  blockLabels,
  canContain,
  designMessages,
  findBlock,
  labelFor,
  MAX_BYTES,
  sectionsFor,
  voidTags,
  type DesignBlock,
  type Breakpoint,
  type Interaction,
  type DesignDrag,
  type DesignSelection,
  type ThemeDocument,
} from './types';

type DesignEvents = Pick<
  HTMLAttributes<Element>,
  'draggable' | 'tabIndex' | 'onDragStart' | 'onDragOver' | 'onDrop' | 'onClick' | 'onKeyDown'
>;

interface ContentProps {
  item?: ContentItem | null;
  items?: ContentItem[];
  featured?: ContentItem | null;
  related?: ContentItem[];
  collection?: PublicCollection | null;
  pagination?: PageLinks;
  query?: string;
  category?: string;
  archiveUrl?: string;
  categories?: string[];
  fieldFilters?: Record<string, string>;
  tag?: { slug: string } | null;
  templateFallback?: string;
  count?: number;
  resultCount?: number;
}

export default function DesignPage({
  name,
  pageProps,
}: {
  name: string;
  pageProps: Record<string, unknown>;
}) {
  const { t } = useTranslation();
  const { props, url } = usePage<SharedProps>();
  const { theme, site = defaultSite, navigation, pluginNavigation } = props;
  const [document, setDocument] = useState<ThemeDocument>(theme!.design!);
  const [selection, setSelection] = useState<DesignSelection | null>(null);
  const [feeds, setFeeds] = useState<Record<string, ContentItem[]>>(props.themeFeeds || {});
  const [preview, setPreview] = useState<{
    breakpoint: Breakpoint;
    interaction: Interaction;
    styleClass: string;
  }>({ breakpoint: 'desktop', interaction: 'normal', styleClass: '' });
  const [easy, setEasy] = useState(true);
  const session = theme?.studioSession;
  const editing = Boolean(session);
  const content = pageProps as ContentProps;
  const selectedTemplate =
    theme?.studioScope ||
    (Object.hasOwn(document.templates, name) ? name : content.templateFallback || 'Home');
  const scope =
    selectedTemplate.startsWith('@') || Object.hasOwn(document.templates, selectedTemplate)
      ? selectedTemplate
      : 'Home';
  const { item, collection } = content;
  const visibleItems = content.featured
    ? [content.featured, ...(content.items || [])]
    : content.items || [];
  const siteValues = Object.fromEntries(
    Object.keys(defaultSite).map((key) => [key, site[key as keyof typeof site]]),
  ) as unknown as SharedProps['site'];
  const context: BindingContext = {
    site: siteValues,
    item,
    collection: collection as unknown as Record<string, unknown>,
    page: {
      count: content.count || 0,
      resultCount: content.resultCount || 0,
      query: content.query || '',
      category: content.category || '',
      archiveUrl: content.archiveUrl || '',
    },
  };
  let rendered = 0;

  const inline = useInlineText(editing && easy, (target, text) => {
    setDocument((previous) => {
      const next = structuredClone(previous);
      const section = sectionsFor(next, target.scope).find(
        (section) => section.id === target.section,
      );
      const node = findBlock(section?.blocks || [], target.block);
      if (node && editableText(node)) node.text = text;
      return next;
    });
    send(designMessages.editText, { selection: target, text });
  });
  function send(type: string, data: Record<string, unknown> = {}) {
    if (session && window.parent !== window)
      window.parent.postMessage({ type, session, themeId: theme!.id, ...data }, location.origin);
  }
  useEffect(() => {
    setDocument(theme!.design!);
    setFeeds(props.themeFeeds || {});
  }, [theme?.design, props.themeFeeds]);
  useEffect(() => {
    if (!session || window.parent === window) return;
    const receive = (event: MessageEvent) => {
      if (event.origin !== location.origin || event.source !== window.parent) return;
      const message = event.data;
      if (message?.session !== session || message.themeId !== theme!.id) return;
      if (message.type === designMessages.request) send(designMessages.ready);
      if (message.type !== designMessages.update || ![1, 2].includes(message.document?.schema))
        return;
      if (JSON.stringify(message.document).length > MAX_BYTES) return;
      setEasy(message.mode !== 'advanced');
      setDocument(message.document);
      setSelection(message.selection || null);
      setPreview({
        breakpoint: ['desktop', 'tablet', 'mobile'].includes(message.breakpoint)
          ? message.breakpoint
          : 'desktop',
        interaction: ['normal', 'hover', 'focus'].includes(message.interaction)
          ? message.interaction
          : 'normal',
        styleClass: message.styleClass || '',
      });
      if (message.feeds) setFeeds(message.feeds);
    };
    window.addEventListener('message', receive);
    send(designMessages.ready);
    return () => window.removeEventListener('message', receive);
  }, [session, theme?.id, scope]);
  useEffect(() => {
    if (!editing || !selection) return;
    const id = selection.block || selection.section;
    const element = window.document.querySelector<HTMLElement>(
      `[data-design-node="${CSS.escape(id)}"]`,
    );
    element?.scrollIntoView({ block: 'nearest', inline: 'nearest', behavior: 'auto' });
  }, [editing, selection?.scope, selection?.section, selection?.block]);

  function dragStart(event: DragEvent, target: DesignDrag) {
    event.stopPropagation();
    event.dataTransfer.setData('application/x-haxepress-design', JSON.stringify(target));
    event.dataTransfer.effectAllowed = 'move';
  }
  function drop(event: DragEvent, target: DesignDrag) {
    event.preventDefault();
    event.stopPropagation();
    const preset = event.dataTransfer.getData('application/x-haxepress-preset');
    if (preset) {
      send(designMessages.insert, { preset, target });
      return;
    }
    try {
      send(designMessages.move, {
        source: JSON.parse(event.dataTransfer.getData('application/x-haxepress-design')),
        target,
      });
    } catch {
      /* Unrelated drag sources do not change a design. */
    }
  }
  function interactions(
    target: DesignSelection,
    editable: boolean,
    container = false,
  ): DesignEvents {
    if (!editing || !editable) return {};
    return {
      draggable: true,
      tabIndex: 0,
      onDragStart: (event: DragEvent) => dragStart(event, target),
      onDragOver: (event: DragEvent) => {
        event.preventDefault();
        event.stopPropagation();
      },
      onDrop: (event: DragEvent) =>
        drop(event, { ...target, position: container ? 'inside' : 'before' }),
      onClick: (event: MouseEvent) => {
        if (inline.id === target.block) {
          event.stopPropagation();
          return;
        }
        event.preventDefault();
        event.stopPropagation();
        send(designMessages.select, { selection: target });
      },
      onKeyDown: (event: KeyboardEvent) => {
        if (event.key === 'Enter') {
          event.preventDefault();
          event.stopPropagation();
          send(designMessages.select, { selection: target });
        }
      },
    };
  }
  function filters() {
    return content.archiveUrl && collection ? (
      <ContentFilters
        collection={collection}
        path={content.archiveUrl}
        query={content.query || ''}
        category={content.category || ''}
        categories={content.categories || []}
        fieldFilters={content.fieldFilters || {}}
        tag={content.tag?.slug}
      />
    ) : null;
  }
  function renderBlocks(
    nodes: DesignBlock[],
    sectionId: string,
    ownerScope: string,
    data: BindingContext,
    depth = 0,
    editable = true,
  ): ReactNode {
    if (depth > 32) return null;
    return nodes.map((node) => {
      if (++rendered > 20000) return null;
      const visible = isVisible(node, data);
      if (!visible && !editing) return null;
      const target = { scope: ownerScope, section: sectionId, block: node.id };
      const selected =
        selection?.scope === ownerScope &&
        selection.section === sectionId &&
        selection.block === node.id;
      const classes = `hp-design-node ${classNames(node.classes)}${selected ? ' is-selected' : ''}${!visible ? ' is-condition-hidden' : ''}`;
      const common = {
        'data-design-node': node.id,
        'data-block-id': node.id,
        className: classes,
        ...interactions(target, editable, canContain(node)),
        ...inline.attributes(node),
        onDoubleClick:
          editing && easy && editable
            ? (event: MouseEvent) => {
                event.preventDefault();
                event.stopPropagation();
                if (node.type === 'image' && !node.bindings?.image)
                  send(designMessages.chooseImage, { selection: target });
                else inline.start(node, target);
              }
            : undefined,
      };
      const text = boundText(node, 'text', node.text, data);
      const href = linkValue(boundText(node, 'href', node.href, data));
      // Matches the server: a new tab gets no access to this page.
      const linkTarget = node.newTab ? { target: '_blank', rel: 'noopener noreferrer' } : {};
      const image = imageValue(
        boundText(node, 'image', node.image, data),
        props.mediaRules?.imagePattern,
        props.theme?.id,
      );
      const alt = boundText(node, 'alt', node.alt, data);
      const children = () =>
        renderBlocks(node.children || [], sectionId, ownerScope, data, depth + 1, editable);
      const title = node.name || t(blockLabels[node.type]);
      const blockImage = image ? (
        <img className="hp-design-image" src={image} alt={alt} loading="lazy" />
      ) : editing ? (
        <span className="hp-design-placeholder">{t('Choose an image')}</span>
      ) : null;
      let element: ReactNode;
      switch (node.type) {
        case 'container':
          element = (
            <div {...common} aria-label={editing ? title : undefined}>
              {children()}
              {editing && !node.children?.length && (
                <span className="hp-design-drop-label">{t('Drop elements here')}</span>
              )}
            </div>
          );
          break;
        case 'element': {
          const attributes: Record<string, unknown> = { ...node.attributes };
          for (const boolean of ['required', 'disabled', 'open'])
            if (attributes[boolean] !== undefined)
              attributes[boolean] = attributes[boolean] !== 'false' && attributes[boolean] !== '0';
          if (attributes.checked !== undefined) {
            attributes.defaultChecked =
              attributes.checked !== 'false' && attributes.checked !== '0';
            delete attributes.checked;
          }
          if (attributes.for) {
            attributes.htmlFor = attributes.for;
            delete attributes.for;
          }
          if (attributes.value !== undefined || node.bindings?.value) {
            attributes.defaultValue = boundText(
              node,
              'value',
              String(attributes.value || ''),
              data,
            );
            delete attributes.value;
          }
          const datetime = boundText(
            node,
            'datetime',
            String(attributes.datetime || attributes.dateTime || ''),
            data,
          );
          if (datetime) {
            attributes.dateTime = datetime;
            delete attributes.datetime;
          }
          if (node.tag === 'a') {
            attributes.href = href || '/';
            if (node.newTab) Object.assign(attributes, linkTarget);
          }
          const actualChildren = voidTags.includes(node.tag || '') ? undefined : (
            <>
              {text}
              {children()}
              {editing && !text && !node.children?.length && (
                <span className="hp-design-drop-label">{title}</span>
              )}
            </>
          );
          element = createElement(node.tag || 'div', { ...attributes, ...common }, actualChildren);
          break;
        }
        case 'heading':
          element = createElement(
            `h${node.level}`,
            common,
            href ? (
              <SiteLink href={href} {...linkTarget}>
                {text}
              </SiteLink>
            ) : (
              text
            ),
          );
          break;
        case 'text':
          element = (
            <p {...common} className={`${classes} hp-design-text`}>
              {text}
            </p>
          );
          break;
        case 'image':
          element = href ? (
            <SiteLink
              {...common}
              {...linkTarget}
              className={`${classes} hp-design-image-link`}
              href={href}
            >
              {blockImage}
            </SiteLink>
          ) : (
            <figure {...common} className={`${classes} hp-design-image-node`}>
              {blockImage}
            </figure>
          );
          break;
        case 'button':
          element = (
            <SiteLink
              {...common}
              {...linkTarget}
              className={`${classes} hp-design-button`}
              href={href || '/'}
            >
              {text}
            </SiteLink>
          );
          break;
        case 'spacer':
          element = (
            <div
              {...common}
              className={`${classes} hp-design-spacer`}
              style={{ minHeight: node.level * 16 }}
            />
          );
          break;
        case 'divider':
          element = <hr {...common} />;
          break;
        case 'brand':
          element = (
            <SiteLink {...common} className={`${classes} hp-design-brand`} href="/">
              {site.site_logo ? <img src={site.site_logo} alt={site.site_name} /> : site.site_name}
            </SiteLink>
          );
          break;
        case 'navigation': {
          const region = ownerScope === 'footer' ? 'footer' : 'header';
          element = (
            <nav
              {...common}
              aria-label={t(region === 'header' ? 'Main navigation' : 'Footer navigation')}
            >
              <SiteNavigation links={navigation?.[region] || []} path={url.split('?')[0]} />
              {pluginNavigation?.[region]?.map((link) => (
                <SiteLink key={link.id} href={link.href}>
                  {t(link.label)}
                </SiteLink>
              ))}
            </nav>
          );
          break;
        }
        case 'site-description':
          element = (
            <p {...common}>
              {scope === 'About' ? site.about_site || site.description : site.description}
            </p>
          );
          break;
        case 'content-title':
          element = <h1 {...common}>{data.item?.title || (editing ? t('Content title') : '')}</h1>;
          break;
        case 'content-excerpt':
          element = (
            <p {...common} className={`${classes} hp-design-excerpt`}>
              {data.item?.excerpt || (editing ? t('Content excerpt') : '')}
            </p>
          );
          break;
        case 'content-image':
          element = (
            <figure {...common} className={`${classes} hp-design-image-node`}>
              {data.item?.image ? (
                <img className="hp-design-image" src={data.item.image} alt={data.item.image_alt} />
              ) : editing ? (
                <span className="hp-design-placeholder">{t('Content image')}</span>
              ) : null}
            </figure>
          );
          break;
        case 'content-body':
          element = (
            <div {...common} className={`${classes} hp-design-prose`}>
              <ExtensionSlot name="content.before" />
              <Markdown
                content={
                  data.item?.content ||
                  (editing ? t('The selected content body appears here.') : '')
                }
              />
              <FieldValues definitions={data.item?.fieldDefinitions} values={data.item?.fields} />
              <ExtensionSlot name="content.after" />
            </div>
          );
          break;
        case 'repeat': {
          const source = node.source || 'page.items';
          const rows = source.startsWith('feed:')
            ? feeds[source.slice(5)] || []
            : source === 'page.related'
              ? content.related || []
              : visibleItems;
          element = (
            <div {...common} className={`${classes} hp-design-repeater`}>
              {rows.map((entry) => (
                <Fragment key={entry.id}>
                  {renderBlocks(
                    node.children || [],
                    sectionId,
                    ownerScope,
                    { ...data, item: entry },
                    depth + 1,
                    editable,
                  )}
                </Fragment>
              ))}
              {rows.length === 0 && editing && (
                <span className="hp-design-placeholder">
                  {t('No records in this source. Edit its filters or add published content.')}
                </span>
              )}
              {!node.children?.length && editing && (
                <span className="hp-design-drop-label">
                  {t('Add elements to design each repeated item.')}
                </span>
              )}
            </div>
          );
          break;
        }
        case 'component': {
          const component = document.components?.[node.component || ''];
          element = (
            <div {...common} className={`${classes} hp-design-component`}>
              {component ? (
                renderSections(component.sections, ownerScope, data, depth + 1, false)
              ) : editing ? (
                <span className="hp-design-placeholder">{t('Choose a reusable component')}</span>
              ) : null}
            </div>
          );
          break;
        }
        case 'extension':
          element = (
            <div {...common}>
              <ExtensionSlot name={node.slot || 'site.footer'} />
            </div>
          );
          break;
        case 'pagination':
          element = (
            <div {...common}>
              {content.pagination ? (
                <Pagination links={content.pagination} count={content.items?.length || 0} />
              ) : editing ? (
                <span className="hp-design-drop-label">{t('Archive pagination')}</span>
              ) : null}
            </div>
          );
          break;
        case 'search':
          element = (
            <div {...common}>
              {filters() ||
                (editing ? (
                  <span className="hp-design-drop-label">{t('Archive search and filters')}</span>
                ) : null)}
            </div>
          );
          break;
        case 'content-list': {
          const rows = visibleItems.length ? visibleItems : content.related || [];
          element = (
            <div {...common}>
              {filters()}
              <div className="hp-design-content-grid">
                {rows.map((entry) => (
                  <article key={entry.id}>
                    {entry.image && (
                      <SiteLink href={entry.url} tabIndex={-1}>
                        <img src={entry.image} alt={entry.image_alt} loading="lazy" />
                      </SiteLink>
                    )}
                    <h2>
                      <SiteLink href={entry.url}>{entry.title}</SiteLink>
                    </h2>
                    {entry.excerpt && <p>{entry.excerpt}</p>}
                    <time dateTime={entry.published_at}>{entry.publishedLabel}</time>
                  </article>
                ))}
              </div>
              {!rows.length && <p>{t('No content here just yet.')}</p>}
              {content.pagination && <Pagination links={content.pagination} count={rows.length} />}
              {scope === 'Home' && collection?.hasArchive && (
                <SiteLink className="hp-design-archive" href={collection.publicBase}>
                  {t('All content')}
                </SiteLink>
              )}
            </div>
          );
          break;
        }
      }
      return <Fragment key={`${node.id}:${inline.revisions[node.id] || 0}`}>{element}</Fragment>;
    });
  }
  function renderSections(
    sections: ReturnType<typeof sectionsFor>,
    ownerScope: string,
    data = context,
    depth = 0,
    editable = true,
  ): ReactNode {
    return sections.map((section) => {
      const selected =
        selection?.scope === ownerScope && selection.section === section.id && !selection.block;
      const target = { scope: ownerScope, section: section.id };
      const customLayout = Boolean(
        section.styles?.desktop?.normal?.display ||
        section.styles?.tablet?.normal?.display ||
        section.styles?.mobile?.normal?.display,
      );
      return (
        <section
          key={section.id}
          data-design-node={section.id}
          data-section-id={section.id}
          data-design-align={section.align}
          className={`hp-design-section ${classNames(section.classes)}${selected ? ' is-selected' : ''}${editing && editable ? ' is-editable' : ''}`}
          onClick={
            editing && editable
              ? (event) => {
                  event.preventDefault();
                  event.stopPropagation();
                  send(designMessages.select, { selection: target });
                }
              : undefined
          }
          onDragOver={
            editing && editable
              ? (event) => {
                  event.preventDefault();
                  event.stopPropagation();
                }
              : undefined
          }
          onDrop={
            editing && editable
              ? (event) => drop(event, { ...target, position: 'inside' })
              : undefined
          }
        >
          {editing && editable && (
            <button
              type="button"
              className="hp-design-section-handle"
              draggable
              onDragStart={(event) => dragStart(event, target)}
              onClick={(event) => {
                event.stopPropagation();
                send(designMessages.select, { selection: target });
              }}
            >
              {section.name || t('Section')}
            </button>
          )}
          {customLayout ? (
            renderBlocks(section.blocks, section.id, ownerScope, data, depth, editable)
          ) : (
            <div
              className={`hp-design-section-inner width-${section.width}`}
              style={{ '--design-columns': section.columns } as CSSProperties}
            >
              {renderBlocks(section.blocks, section.id, ownerScope, data, depth, editable)}
              {editing && !section.blocks.length && (
                <span className="hp-design-drop-label">{t('Drop elements here')}</span>
              )}
            </div>
          )}
        </section>
      );
    });
  }
  const tokens = document.tokens;
  const font =
    tokens.font === 'serif'
      ? "'DM Serif Display', Georgia, serif"
      : tokens.font === 'sans'
        ? "'DM Sans', Arial, sans-serif"
        : tokens.font;
  const style = {
    '--design-background': tokens.background,
    '--design-text': tokens.text,
    '--design-accent': tokens.accent,
    '--design-width': `${tokens.width}px`,
    '--design-radius': `${tokens.radius}px`,
    '--design-font': font,
  } as CSSProperties;
  return (
    <div
      className={`cms-site hp-design${editing ? ' hp-design-editing' : ''}${editing && easy ? ' hp-design-easy' : ''}`}
      data-cms-site
      data-layout="builder"
      style={style}
      onClickCapture={
        editing
          ? (event) => {
              const target = event.target as Element;
              if (target.closest('[contenteditable="plaintext-only"]')) return;
              if (target.closest('a,button,input,select,textarea,form')) event.preventDefault();
            }
          : undefined
      }
      onSubmitCapture={editing ? (event) => event.preventDefault() : undefined}
    >
      <PageHead
        title={
          item?.seo_title ||
          item?.title ||
          (scope === 'Home'
            ? site.site_name
            : scope === 'ContentIndex'
              ? collection?.name || t('Content')
              : t(labelFor(document, scope)))
        }
        description={item?.seo_description || item?.excerpt || site.description}
      />
      <style data-design-styles>
        {designStyles(document, selection, editing ? preview : undefined)}
      </style>
      <PublicExtensions />
      {editing && (
        <DesignOverlay
          selection={selection}
          document={document}
          simple={easy}
          onResize={(selection, width, height) =>
            send(designMessages.resize, { selection, width, height })
          }
        />
      )}
      <a className="skip-link" href="#main">
        {t('Skip to content')}
      </a>
      {!scope.startsWith('@') && (
        <>
          <ExtensionSlot name="site.top" />
          <header>{renderSections(document.header, 'header')}</header>
        </>
      )}
      <main id="main">
        {renderSections(sectionsFor(document, scope), scope)}
        {editing && !sectionsFor(document, scope).length && (
          <div className="hp-design-empty">{t('Add your first section from the editor.')}</div>
        )}
      </main>
      {!scope.startsWith('@') && (
        <>
          <ExtensionSlot name="site.before-footer" />
          <footer>{renderSections(document.footer, 'footer')}</footer>
          <ExtensionSlot name="site.footer" />
        </>
      )}
    </div>
  );
}
