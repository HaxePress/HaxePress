import type { ReactNode } from 'react';
import type { SharedProps } from '../../../../../resources/js/types';
import type {
  ThemeRuntime,
  ThemeLayout,
  ThemeContentCard,
} from '../../../../../resources/js/themes/types';

export function createAbout(runtime: ThemeRuntime, SiteLayout: ThemeLayout) {
  const { React, Link, usePage, useTranslation, PageHead, Icon, defaultSite, asset } = runtime;
  function About() {
    const { t } = useTranslation();
    const { primaryArchive = '/' } = usePage<SharedProps>().props;
    const { site = defaultSite } = usePage<SharedProps>().props;
    return (
      <>
        <PageHead title={t('About this site')} />
        <section className="about-page wrap">
          <div className="about-page-copy">
            <p className="intro-label">
              <span /> {t('About this site')}
            </p>
            <h1>{site.site_name}</h1>
            <p className="about-lead">{site.description}</p>
            {site.about_site && <p>{site.about_site}</p>}
            <Link className="button" href={primaryArchive}>
              {t('View content')} <Icon name="arrow-up-right" />
            </Link>
          </div>
          <div className="about-photo">
            <img src={asset('images/forest.jpg')} alt={t('Sunlight in a forest')} />
          </div>
        </section>
      </>
    );
  }
  About.layout = (page: ReactNode) => <SiteLayout>{page}</SiteLayout>;
  return About;
}
