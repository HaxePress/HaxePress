import { Head, usePage } from '@inertiajs/react';
import { defaultSite, type SharedProps } from '../types';
import { useEffect } from 'react';
import { useTranslation } from '../i18n';

export default function PageHead({
  title,
  admin = false,
  description,
  exactTitle = false,
}: {
  title: string;
  admin?: boolean;
  description?: string;
  exactTitle?: boolean;
}) {
  const { site = defaultSite } = usePage<SharedProps>().props;
  const { locale, direction, t } = useTranslation();
  useEffect(() => {
    document.documentElement.lang = locale;
    document.documentElement.dir = direction;
  }, [locale, direction]);
  const administration = admin ? ' ' + t('Administration') : '';
  const pageTitle = exactTitle ? title : title + ' — ' + site.site_name + administration;
  return (
    <Head title={pageTitle}>
      <meta head-key="description" name="description" content={description || site.description} />
      {admin && <meta head-key="robots" name="robots" content="noindex,nofollow" />}
    </Head>
  );
}
