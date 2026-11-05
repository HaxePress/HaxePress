import { usePage } from '@inertiajs/react';
import type { SharedProps } from '../types';
import { SiteLink as Link } from '../themes/navigation';
import type { ReactNode } from 'react';
import { useTranslation } from '../i18n';
import SiteLayout from '../layouts/SiteLayout';
import PageHead from '../components/PageHead';

export default function NotFound() {
  const { t } = useTranslation();
  const { primaryArchive = '/' } = usePage<SharedProps>().props;
  return (
    <>
      <PageHead title={t('Page not found')} />
      <div className="simple-empty">
        <h1>{t('Page not found')}</h1>
        <p>{t('Check the address or browse content.')}</p>
        <Link href={primaryArchive}>{t('Back to content')}</Link>
      </div>
    </>
  );
}
NotFound.layout = (page: ReactNode) => <SiteLayout>{page}</SiteLayout>;
