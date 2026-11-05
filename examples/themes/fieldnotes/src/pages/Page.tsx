import type { ReactNode } from 'react';
import type { ContentItem } from '../../../../../resources/js/types';
import type {
  ThemeRuntime,
  ThemeLayout,
  ThemeContentCard,
} from '../../../../../resources/js/themes/types';

export function createPage(runtime: ThemeRuntime, SiteLayout: ThemeLayout) {
  const { React, PageHead, Markdown, FieldValues, ExtensionSlot } = runtime;
  function Page({ item }: { item: ContentItem }) {
    return (
      <>
        <PageHead
          title={item.seo_title || item.title}
          exactTitle={Boolean(item.seo_title)}
          description={item.seo_description || item.excerpt}
        />
        <article className="content-page wrap content-page">
          <header className="content-header">
            <h1>{item.title}</h1>
            {item.excerpt && <p className="content-deck">{item.excerpt}</p>}
          </header>
          {item.image && <img className="content-cover" src={item.image} alt={item.image_alt} />}
          <div className="content-prose">
            <ExtensionSlot name="content.before" />
            <Markdown content={item.content || ''} />
            <FieldValues definitions={item.fieldDefinitions} values={item.fields} />
            <ExtensionSlot name="content.after" />
          </div>
        </article>
      </>
    );
  }
  Page.layout = (page: ReactNode) => <SiteLayout>{page}</SiteLayout>;
  return Page;
}
