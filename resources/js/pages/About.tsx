import { SiteLink as Link } from '../themes/navigation';
import { usePage } from '@inertiajs/react';
import type { ReactNode } from 'react';
import { useTranslation } from '../i18n';
import { defaultSite, type SharedProps } from '../types';
import SiteLayout from '../layouts/SiteLayout';
import PageHead from '../components/PageHead';

export default function About() {
  const { t } = useTranslation();
  const { primaryArchive = '/' } = usePage<SharedProps>().props;
  const { site = defaultSite } = usePage<SharedProps>().props;
  return (
    <>
      <PageHead title={t('About this site')} />
      <article className="simple-about">
        <h1>{site.site_name}</h1>
        {site.description && <p>{site.description}</p>}
        {site.about_site && <p>{site.about_site}</p>}
        <Link href={primaryArchive}>{t('Explore content')}</Link>
      </article>
    </>
  );
}
About.layout = (page: ReactNode) => <SiteLayout>{page}</SiteLayout>;
