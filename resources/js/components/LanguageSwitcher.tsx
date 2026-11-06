import { usePage } from '@inertiajs/react';
import { useTranslation } from '../i18n';

export default function LanguageSwitcher() {
  const { locale, locales, t } = useTranslation();
  const { url } = usePage();
  const destination = new URL(url, 'http://localhost');
  destination.searchParams.delete('lang');
  return (
    <form className="language-switcher" method="post" action="/locale">
      <input
        type="hidden"
        name="return_to"
        value={`${destination.pathname}${destination.search}${destination.hash}`}
      />
      <label>
        <span className="sr-only">{t('Language')}</span>
        <select
          name="locale"
          value={locale}
          aria-label={t('Language')}
          onChange={(event) => event.currentTarget.form?.requestSubmit()}
        >
          {locales.map((choice) => (
            <option key={choice.code} value={choice.code} lang={choice.code}>
              {choice.name}
            </option>
          ))}
        </select>
      </label>
      <noscript>
        <button type="submit">{t('Change language')}</button>
      </noscript>
    </form>
  );
}
