import { Link, useForm, usePage } from '@inertiajs/react';
import { useState, type ReactNode } from 'react';
import AdminLayout from '../../layouts/AdminLayout';
import PageHead from '../../components/PageHead';
import Alert from '../../components/Alert';
import Icon from '../../components/Icon';
import FriendlyPreview from '../../themes/builder/FriendlyPreview';
import {
  friendlyDocument,
  paletteChoices,
  starterChoices,
  type StarterChoice,
} from '../../themes/builder/friendly-presets';
import type { ThemeDocument } from '../../themes/builder/types';
import { useTranslation } from '../../i18n';
import { errorText, type SharedProps } from '../../types';

export default function ThemeCreate({ baseDocument }: { baseDocument: ThemeDocument }) {
  const { t } = useTranslation();
  const { csrfToken } = usePage<SharedProps>().props;
  const [step, setStep] = useState(0);
  const [choice, setChoice] = useState<StarterChoice>('business');
  const [accent, setAccent] = useState<string>(paletteChoices[0].value);
  const [font, setFont] = useState('sans');
  const form = useForm({ name: 'My website', starter: 'blank' });
  const selected = starterChoices.find((starter) => starter.id === choice)!;
  const steps = ['Choose a starting point', 'Make it yours', 'Ready to build'];
  return (
    <>
      <PageHead title={t('Create your website design')} admin />
      <div className="admin-page-heading">
        <h1>{t('Create your website design')}</h1>
        <Link className="button button-outline" href="/admin/themes">
          {t('Back to themes')}
        </Link>
      </div>
      <form
        className="easy-create"
        onSubmit={(event) => {
          event.preventDefault();
          if (step < 2) {
            setStep((value) => value + 1);
            return;
          }
          const design = friendlyDocument(baseDocument, choice, accent, font);
          form.transform((values) => ({
            ...values,
            design: JSON.stringify(design),
            _token: csrfToken,
          }));
          form.post('/admin/themes/create');
        }}
      >
        <ol className="easy-wizard-steps" aria-label={t('Create a design')}>
          {steps.map((label, index) => (
            <li key={label} aria-current={step === index ? 'step' : undefined}>
              <span>{index < step ? <Icon name="check" /> : index + 1}</span>
              <span>{t(label)}</span>
            </li>
          ))}
        </ol>
        <Alert error message={errorText(form.errors)} />
        {step === 0 && (
          <div className="easy-wizard-body">
            <h2>{t('What would you like to make?')}</h2>
            <p>{t('Choose a starting point. You can change everything later.')}</p>
            <div
              className="easy-starting-points"
              role="radiogroup"
              aria-label={t('Starting design')}
            >
              {starterChoices.map((starter) => (
                <label
                  key={starter.id}
                  className={`easy-starter-card${choice === starter.id ? ' is-selected' : ''}`}
                >
                  <input
                    type="radio"
                    name="starting-design"
                    value={starter.id}
                    checked={choice === starter.id}
                    onChange={() => setChoice(starter.id)}
                  />
                  <FriendlyPreview kind={starter.id} accent={accent} />
                  <span className="easy-starter-heading">
                    <strong>{t(starter.name)}</strong>
                    <span className="easy-starter-check">
                      <Icon name="check" />
                    </span>
                  </span>
                  <small>{t(starter.description)}</small>
                </label>
              ))}
            </div>
          </div>
        )}
        {step === 1 && (
          <div className="easy-wizard-body easy-personalize">
            <div>
              <h2>{t('Add your own touch')}</h2>
              <label className="easy-field">
                {t('Name this design')}
                <input
                  autoFocus
                  aria-label={t('Name this design')}
                  value={form.data.name}
                  required
                  minLength={2}
                  maxLength={100}
                  onChange={(event) => form.setData('name', event.target.value)}
                  placeholder={t('My website')}
                />
                <small>{t('This name helps you find your design in the admin panel.')}</small>
              </label>
              <fieldset className="easy-wizard-palette">
                <legend>{t('Choose a color')}</legend>
                <div className="easy-palette">
                  {paletteChoices.map((palette) => (
                    <button
                      key={palette.name}
                      type="button"
                      style={{ background: palette.value }}
                      aria-label={t(palette.name)}
                      aria-pressed={accent === palette.value}
                      onClick={() => setAccent(palette.value)}
                    >
                      {accent === palette.value ? '✓' : ''}
                    </button>
                  ))}
                </div>
              </fieldset>
              <fieldset>
                <legend>{t('Choose a writing style')}</legend>
                <div className="easy-fonts">
                  {[
                    { name: 'Modern', value: 'sans', font: 'DM Sans' },
                    { name: 'Classic', value: 'serif', font: 'DM Serif Display' },
                  ].map((style) => (
                    <button
                      type="button"
                      key={style.value}
                      aria-pressed={font === style.value}
                      onClick={() => setFont(style.value)}
                    >
                      <span style={{ fontFamily: style.font }}>Aa</span>
                      {t(style.name)}
                    </button>
                  ))}
                </div>
              </fieldset>
            </div>
            <aside className="easy-wizard-preview">
              <FriendlyPreview kind={choice} accent={accent} />
              <strong>{form.data.name || t('My website')}</strong>
              <span>{t(selected.name)}</span>
            </aside>
          </div>
        )}
        {step === 2 && (
          <div className="easy-wizard-body easy-wizard-ready">
            <div className="easy-ready-picture">
              <FriendlyPreview kind={choice} accent={accent} />
            </div>
            <div>
              <h2>{t('Your starting point is ready')}</h2>
              <p>
                {t(
                  'Next, click the words and pictures to change them. Add sections whenever you like.',
                )}
              </p>
              <dl>
                <div>
                  <dt>{t('Design')}</dt>
                  <dd>{form.data.name}</dd>
                </div>
                <div>
                  <dt>{t('Starting point')}</dt>
                  <dd>{t(selected.name)}</dd>
                </div>
              </dl>
              <p className="easy-safe-note">
                <Icon name="eye-off" />
                {t('Your current website stays as it is until you choose Publish website.')}
              </p>
            </div>
          </div>
        )}
        <footer className="easy-wizard-actions">
          <button
            type="button"
            className="button button-outline"
            disabled={step === 0 || form.processing}
            onClick={() => setStep((value) => value - 1)}
          >
            <Icon name="arrow-left" />
            {t('Back')}
          </button>
          <span>{t('Step {current} of {total}', { current: step + 1, total: 3 })}</span>
          <button
            className="button"
            type="submit"
            disabled={form.processing || (step > 0 && form.data.name.trim().length < 2)}
          >
            {t(form.processing ? 'Creating…' : step === 2 ? 'Start editing' : 'Continue')}
            <Icon name="arrow-right" />
          </button>
        </footer>
      </form>
    </>
  );
}
ThemeCreate.layout = (page: ReactNode) => <AdminLayout>{page}</AdminLayout>;
