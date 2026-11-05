import { useTranslation } from '../../i18n';
import { Link, useForm, usePage } from '@inertiajs/react';
import { useState } from 'react';
import PageHead from '../../components/PageHead';
import Icon from '../../components/Icon';
import Alert from '../../components/Alert';
import LanguageSwitcher from '../../components/LanguageSwitcher';
import { defaultSite, errorText, type SharedProps } from '../../types';

export default function Login({ email = '' }: { email?: string }) {
  const { t } = useTranslation();
  const { csrfToken, site = defaultSite, errors } = usePage<SharedProps>().props;
  const [visible, setVisible] = useState(false);
  const form = useForm({ email, password: '' });

  return (
    <div className="login-body">
      <PageHead title={t('Sign in')} admin />
      <main className="login-panel">
        <Link className="back-link" href="/">
          <Icon name="arrow-left" /> {t('Back to website')}
        </Link>
        <div className="login-form-wrap">
          <p className="login-context">{site.site_name}</p>
          <h1>{t('Sign in')}</h1>
          <Alert error message={errorText(form.errors) || errorText(errors?.credentials)} />
          <form
            action="/admin/login"
            method="post"
            className="login-form"
            onSubmit={(event) => {
              event.preventDefault();
              form.transform((data) => ({ ...data, _token: csrfToken }));
              form.post('/admin/login', { onFinish: () => form.reset('password') });
            }}
          >
            <input type="hidden" name="_token" value={csrfToken || ''} />
            <label htmlFor="email">{t('Email address')}</label>
            <input
              id="email"
              name="email"
              type="email"
              placeholder={t('you@example.com')}
              autoComplete="username"
              value={form.data.email}
              onChange={(event) => form.setData('email', event.target.value)}
              required
              autoFocus
            />
            <label htmlFor="password">{t('Password')}</label>
            <div className="password-input">
              <input
                id="password"
                name="password"
                type={visible ? 'text' : 'password'}
                placeholder={t('Your password')}
                autoComplete="current-password"
                value={form.data.password}
                onChange={(event) => form.setData('password', event.target.value)}
                required
              />
              <button
                type="button"
                className="icon-button"
                onClick={() => setVisible(!visible)}
                aria-pressed={visible}
                aria-label={visible ? t('Hide password') : t('Show password')}
              >
                <Icon name={visible ? 'eye-off' : 'eye'} />
              </button>
            </div>
            <button type="submit" className="button login-submit" disabled={form.processing}>
              {form.processing ? t('Signing in…') : t('Sign in')}
            </button>
          </form>
        </div>
        <footer className="login-bottom">
          <LanguageSwitcher />
        </footer>
      </main>
    </div>
  );
}
