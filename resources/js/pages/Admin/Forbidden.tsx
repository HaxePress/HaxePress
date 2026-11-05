import { useTranslation } from '../../i18n';
import { Link } from '@inertiajs/react';
import type { ReactNode } from 'react';
import AdminLayout from '../../layouts/AdminLayout';
import PageHead from '../../components/PageHead';

export default function Forbidden({ message }: { message: string }) {
  const { t } = useTranslation();
  return (
    <>
      <PageHead title={t('Access restricted')} admin />
      <section className="admin-card empty-state">
        <h1>{t('Access restricted')}</h1>
        <p>{t(message)}</p>
        <Link href="/admin" className="button">
          {t('Back to overview')}
        </Link>
      </section>
    </>
  );
}
Forbidden.layout = (page: ReactNode) => <AdminLayout>{page}</AdminLayout>;
