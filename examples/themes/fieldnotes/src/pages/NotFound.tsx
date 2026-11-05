import type { SharedProps } from '../../../../../resources/js/types';
import type { ReactNode } from 'react';
import type {
  ThemeRuntime,
  ThemeLayout,
  ThemeContentCard,
} from '../../../../../resources/js/themes/types';

export function createNotFound(runtime: ThemeRuntime, SiteLayout: ThemeLayout) {
  const { React, Link, useTranslation, PageHead, Icon, usePage } = runtime;
  function NotFound() {
    const { t } = useTranslation();
    const { primaryArchive = '/' } = usePage<SharedProps>().props;
    return (
      <>
        <PageHead title={t('Page not found')} />
        <div className="wrap empty-state not-found">
          <h1>{t('Page not found')}</h1>
          <p>
            {t("The content item you're looking for may have moved or hasn't been published yet.")}
          </p>
          <Link className="button" href={primaryArchive}>
            {t('View content')} <Icon name="arrow-right" />
          </Link>
        </div>
      </>
    );
  }
  NotFound.layout = (page: ReactNode) => <SiteLayout>{page}</SiteLayout>;
  return NotFound;
}
