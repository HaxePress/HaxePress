import { Head, router } from '@inertiajs/react';
import { useState } from 'react';
import Icon from '../../components/Icon';

interface DatabaseSummary {
  driver: 'sqlite' | 'mysql';
  file: string;
  host: string;
  port: number;
  database: string;
  username: string;
}
interface Setup {
  blocked: boolean;
  message: string;
  database: DatabaseSummary | null;
}
const steps = ['Database', 'Administrator', 'Finish'];

export default function Install({ setup, csrfToken }: { setup: Setup; csrfToken: string | null }) {
  const [step, setStep] = useState(setup.database ? 1 : 0);
  const [database, setDatabase] = useState<DatabaseSummary | null>(setup.database);
  const [fields, setFields] = useState({
    driver: setup.database?.driver || 'sqlite',
    file: setup.database?.file || 'cms.sqlite',
    host: setup.database?.host || '127.0.0.1',
    port: String(setup.database?.port || 3306),
    database: setup.database?.database || '',
    username: setup.database?.username || '',
    password: '',
  });
  const [admin, setAdmin] = useState({
    site_name: 'HaxePress',
    admin_name: '',
    admin_email: '',
    admin_password: '',
    confirm_password: '',
    sample_content: '0',
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [visible, setVisible] = useState(false);

  async function verifyDatabase() {
    setBusy(true);
    setError('');
    try {
      const response = await fetch('/admin/install/database', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
          'X-CSRF-TOKEN': csrfToken || '',
        },
        body: JSON.stringify(fields),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || 'The database could not be verified.');
      setDatabase(result.database);
      setFields((previous) => ({ ...previous, password: '' }));
      setStep(1);
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'The database could not be verified.');
    } finally {
      setBusy(false);
    }
  }

  function review() {
    const bytes = new TextEncoder().encode(admin.admin_password).length;
    if (bytes < 12 || bytes > 72) {
      setError('Use a password between 12 and 72 bytes.');
      return;
    }
    if (admin.admin_password !== admin.confirm_password) {
      setError('The passwords do not match.');
      return;
    }
    setError('');
    setStep(2);
  }

  async function finish() {
    setBusy(true);
    setError('');
    try {
      const response = await fetch('/admin/install/finish', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
          'X-CSRF-TOKEN': csrfToken || '',
        },
        body: JSON.stringify(admin),
      });
      const result = await response.json();
      if (!response.ok) {
        if (response.status === 409) {
          setStep(0);
          setDatabase(null);
        }
        throw new Error(result.error || 'Setup could not be completed.');
      }
      setAdmin((previous) => ({ ...previous, admin_password: '', confirm_password: '' }));
      router.visit('/admin', { replace: true });
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'Setup could not be completed.');
      setBusy(false);
    }
  }

  return (
    <div className="setup-body">
      <Head title="Install HaxePress">
        <meta head-key="robots" name="robots" content="noindex,nofollow" />
      </Head>
      <main className="setup-shell">
        <aside className="setup-sidebar">
          <div className="setup-wordmark">
            <Icon name="layers" />
            HaxePress
          </div>
          <p className="setup-sidebar-title">Installation</p>
          <ol className="setup-steps" aria-label="Installation progress">
            {steps.map((label, index) => (
              <li
                key={label}
                className={
                  !setup.blocked && step === index
                    ? 'current'
                    : !setup.blocked && step > index
                      ? 'complete'
                      : ''
                }
                aria-current={!setup.blocked && step === index ? 'step' : undefined}
              >
                <span className="setup-step-number">
                  {!setup.blocked && step > index ? <Icon name="check" /> : index + 1}
                </span>
                <span>{label}</span>
              </li>
            ))}
          </ol>
          <div className="setup-access">
            <Icon name="lock" />
            <span>{setup.blocked ? 'Setup locked' : 'Trusted connection'}</span>
          </div>
        </aside>
        <section className="setup-content" aria-busy={busy}>
          {setup.blocked ? (
            <>
              <div className="setup-lock-symbol">
                <Icon name="lock" />
              </div>
              <h1>Setup is locked</h1>
              <p className="setup-intro">{setup.message}</p>
              <div className="setup-notice">
                <strong>Server configuration required</strong>
                <p>
                  Allow your IP address in the server’s <code>INSTALL_TRUSTED_IPS</code> setting.
                  Setup stays unavailable until this check passes.
                </p>
                <p>Use a direct connection or an SSH tunnel for installation.</p>
              </div>
            </>
          ) : (
            <>
              <div className="setup-page-heading">
                <span>Step {step + 1} of 3</span>
                <h1>
                  {step === 0
                    ? 'Connect your database'
                    : step === 1
                      ? 'Create your administrator'
                      : 'Ready to install'}
                </h1>
                <p>
                  {step === 0
                    ? 'Choose where HaxePress will store your content and settings.'
                    : step === 1
                      ? 'Set the site name and the account you will use to manage it.'
                      : 'Review your settings. HaxePress will create its tables and save the configuration.'}
                </p>
              </div>
              {error && (
                <div className="setup-error" role="alert">
                  <Icon name="alert" />
                  <span>{error}</span>
                </div>
              )}
              {step === 0 && (
                <form
                  className="setup-form"
                  onSubmit={(event) => {
                    event.preventDefault();
                    void verifyDatabase();
                  }}
                >
                  <fieldset disabled={busy}>
                    <legend className="sr-only">Database connection</legend>
                    <div className="setup-database-types" role="group" aria-label="Database type">
                      <label className={fields.driver === 'sqlite' ? 'selected' : ''}>
                        <input
                          type="radio"
                          name="driver"
                          value="sqlite"
                          checked={fields.driver === 'sqlite'}
                          onChange={() =>
                            setFields((previous) => ({ ...previous, driver: 'sqlite' }))
                          }
                        />
                        <span>
                          <strong>SQLite</strong>
                          <small>A local database file</small>
                        </span>
                      </label>
                      <label className={fields.driver === 'mysql' ? 'selected' : ''}>
                        <input
                          type="radio"
                          name="driver"
                          value="mysql"
                          checked={fields.driver === 'mysql'}
                          onChange={() =>
                            setFields((previous) => ({ ...previous, driver: 'mysql' }))
                          }
                        />
                        <span>
                          <strong>MySQL</strong>
                          <small>An existing database server</small>
                        </span>
                      </label>
                    </div>
                    {fields.driver === 'sqlite' ? (
                      <div className="setup-field">
                        <label htmlFor="database-file">Database filename</label>
                        <input
                          id="database-file"
                          value={fields.file}
                          maxLength={81}
                          required
                          pattern="[A-Za-z0-9][A-Za-z0-9_.-]{0,74}\.sqlite"
                          onChange={(event) =>
                            setFields((previous) => ({ ...previous, file: event.target.value }))
                          }
                        />
                        <p>The file is created inside the configured storage directory.</p>
                      </div>
                    ) : (
                      <>
                        <div className="setup-field-pair">
                          <div className="setup-field">
                            <label htmlFor="database-host">Host</label>
                            <input
                              id="database-host"
                              value={fields.host}
                              maxLength={253}
                              required
                              onChange={(event) =>
                                setFields((previous) => ({ ...previous, host: event.target.value }))
                              }
                            />
                          </div>
                          <div className="setup-field setup-port">
                            <label htmlFor="database-port">Port</label>
                            <input
                              id="database-port"
                              type="number"
                              min={1}
                              max={65535}
                              required
                              value={fields.port}
                              onChange={(event) =>
                                setFields((previous) => ({ ...previous, port: event.target.value }))
                              }
                            />
                          </div>
                        </div>
                        <div className="setup-field">
                          <label htmlFor="database-name">Database name</label>
                          <input
                            id="database-name"
                            autoComplete="off"
                            required
                            maxLength={64}
                            value={fields.database}
                            onChange={(event) =>
                              setFields((previous) => ({
                                ...previous,
                                database: event.target.value,
                              }))
                            }
                          />
                          <p>Use an empty database. Existing data will not be overwritten.</p>
                        </div>
                        <div className="setup-field">
                          <label htmlFor="database-user">Username</label>
                          <input
                            id="database-user"
                            autoComplete="off"
                            required
                            maxLength={100}
                            value={fields.username}
                            onChange={(event) =>
                              setFields((previous) => ({
                                ...previous,
                                username: event.target.value,
                              }))
                            }
                          />
                        </div>
                        <div className="setup-field">
                          <label htmlFor="database-password">Database password</label>
                          <input
                            id="database-password"
                            type="password"
                            autoComplete="off"
                            maxLength={1000}
                            value={fields.password}
                            onChange={(event) =>
                              setFields((previous) => ({
                                ...previous,
                                password: event.target.value,
                              }))
                            }
                          />
                        </div>
                      </>
                    )}
                    <div className="setup-form-actions">
                      <button type="submit" className="button">
                        {busy ? 'Checking database…' : 'Verify connection'}
                      </button>
                    </div>
                  </fieldset>
                </form>
              )}
              {step === 1 && (
                <form
                  className="setup-form"
                  onSubmit={(event) => {
                    event.preventDefault();
                    review();
                  }}
                >
                  <fieldset disabled={busy}>
                    <div className="setup-verified">
                      <Icon name="check" />
                      <span>
                        {database?.driver === 'sqlite' ? database.file : database?.database} ·
                        Connection verified
                      </span>
                    </div>
                    <div className="setup-field">
                      <label htmlFor="setup-site-name">Site name</label>
                      <input
                        id="setup-site-name"
                        value={admin.site_name}
                        required
                        minLength={2}
                        maxLength={100}
                        onChange={(event) =>
                          setAdmin((previous) => ({ ...previous, site_name: event.target.value }))
                        }
                      />
                    </div>
                    <div className="setup-field">
                      <label htmlFor="setup-admin-name">Administrator name</label>
                      <input
                        id="setup-admin-name"
                        autoComplete="name"
                        required
                        minLength={2}
                        maxLength={100}
                        value={admin.admin_name}
                        onChange={(event) =>
                          setAdmin((previous) => ({ ...previous, admin_name: event.target.value }))
                        }
                      />
                    </div>
                    <div className="setup-field">
                      <label htmlFor="setup-admin-email">Email address</label>
                      <input
                        id="setup-admin-email"
                        type="email"
                        autoComplete="username"
                        required
                        maxLength={254}
                        value={admin.admin_email}
                        onChange={(event) =>
                          setAdmin((previous) => ({ ...previous, admin_email: event.target.value }))
                        }
                      />
                    </div>
                    <div className="setup-field">
                      <label htmlFor="setup-admin-password">Administrator password</label>
                      <div className="setup-password">
                        <input
                          id="setup-admin-password"
                          type={visible ? 'text' : 'password'}
                          autoComplete="new-password"
                          required
                          minLength={12}
                          value={admin.admin_password}
                          onChange={(event) =>
                            setAdmin((previous) => ({
                              ...previous,
                              admin_password: event.target.value,
                            }))
                          }
                        />
                        <button
                          type="button"
                          className="icon-button"
                          aria-label={visible ? 'Hide password' : 'Show password'}
                          onClick={() => setVisible(!visible)}
                        >
                          <Icon name={visible ? 'eye-off' : 'eye'} />
                        </button>
                      </div>
                      <p>Use 12–72 bytes. The password is saved in your private .env file.</p>
                    </div>
                    <div className="setup-field">
                      <label htmlFor="setup-confirm-password">Confirm password</label>
                      <input
                        id="setup-confirm-password"
                        type="password"
                        autoComplete="new-password"
                        required
                        value={admin.confirm_password}
                        onChange={(event) =>
                          setAdmin((previous) => ({
                            ...previous,
                            confirm_password: event.target.value,
                          }))
                        }
                      />
                    </div>
                    <div className="setup-form-actions">
                      <button
                        type="button"
                        className="button button-outline"
                        onClick={() => {
                          setError('');
                          setStep(0);
                        }}
                      >
                        Back
                      </button>
                      <button type="submit" className="button">
                        Review settings
                      </button>
                    </div>
                  </fieldset>
                </form>
              )}
              {step === 2 && (
                <div className="setup-form">
                  <dl className="setup-review">
                    <div>
                      <dt>Database</dt>
                      <dd>
                        {database?.driver === 'sqlite'
                          ? 'SQLite · ' + database.file
                          : 'MySQL · ' +
                            database?.host +
                            ':' +
                            database?.port +
                            ' / ' +
                            database?.database}
                      </dd>
                    </div>
                    <div>
                      <dt>Site name</dt>
                      <dd>{admin.site_name}</dd>
                    </div>
                    <div>
                      <dt>Administrator</dt>
                      <dd>
                        {admin.admin_name}
                        <span>{admin.admin_email}</span>
                      </dd>
                    </div>
                    <div>
                      <dt>Configuration</dt>
                      <dd>Private .env file</dd>
                    </div>
                  </dl>
                  <label className="setup-samples">
                    <input
                      type="checkbox"
                      disabled={busy}
                      checked={admin.sample_content === '1'}
                      onChange={(event) =>
                        setAdmin((previous) => ({
                          ...previous,
                          sample_content: event.target.checked ? '1' : '0',
                        }))
                      }
                    />
                    <span>
                      Include sample content
                      <small>Start with example content you can edit or remove.</small>
                    </span>
                  </label>
                  <div className="setup-form-actions">
                    <button
                      type="button"
                      className="button button-outline"
                      disabled={busy}
                      onClick={() => {
                        setError('');
                        setStep(1);
                      }}
                    >
                      Back
                    </button>
                    <button
                      type="button"
                      className="button"
                      disabled={busy}
                      onClick={() => void finish()}
                    >
                      {busy ? 'Installing HaxePress…' : 'Install HaxePress'}
                    </button>
                  </div>
                </div>
              )}
            </>
          )}
        </section>
      </main>
    </div>
  );
}
