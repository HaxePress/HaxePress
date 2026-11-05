import { useTranslation } from '../../i18n';
import { router, useForm, usePage } from '@inertiajs/react';
import { useEffect, useRef, useState, type ReactNode } from 'react';
import AdminLayout from '../../layouts/AdminLayout';
import PageHead from '../../components/PageHead';
import Alert from '../../components/Alert';
import Icon from '../../components/Icon';
import Pagination from '../../components/Pagination';
import { errorText, type SharedProps, type PageLinks } from '../../types';

interface Member {
  id: number;
  name: string;
  email: string;
  role: string;
  active: number;
}
export default function Team({
  members,
  total,
  query,
  pagination,
  notice,
  roleChoices,
}: {
  members: Member[];
  total: number;
  query: string;
  pagination: PageLinks;
  notice: string;
  roleChoices: { key: string; name: string; enabled: number }[];
}) {
  const { t } = useTranslation();
  const { csrfToken, errors, auth } = usePage<SharedProps>().props;
  const empty = {
    id: '',
    name: '',
    email: '',
    role: roleChoices.some((role) => role.key === 'writer' && role.enabled === 1) ? 'writer' : '',
    active: true,
    password: '',
  };
  const form = useForm(empty);
  const [search, setSearch] = useState(query);
  const nameInput = useRef<HTMLInputElement>(null);
  useEffect(() => setSearch(query), [query]);
  const editing = Boolean(form.data.id);
  const ownAccount = form.data.id === String(auth?.admin.id);
  function reset() {
    form.setData(empty);
    form.clearErrors();
  }
  return (
    <>
      <PageHead title={t('Team')} admin />
      <div className="admin-page-heading">
        <div>
          <h1>{t('Your team')}</h1>
        </div>
      </div>
      <Alert message={notice} />
      <Alert error message={errorText(form.errors) || errorText(errors.team)} />
      <div className="categories-grid">
        <section className="admin-card category-collection">
          <div className="admin-card-heading">
            <h2>
              {t('Team members')} <span className="count-badge">{total}</span>
            </h2>
          </div>
          <form
            className="category-search-form"
            onSubmit={(event) => {
              event.preventDefault();
              router.get('/admin/team', { q: search }, { preserveState: true });
            }}
          >
            <label className="sr-only" htmlFor="team-query">
              {t('Find a team member')}
            </label>
            <input
              id="team-query"
              type="search"
              placeholder={t('Search names or email addresses…')}
              maxLength={100}
              value={search}
              onChange={(event) => setSearch(event.target.value)}
            />
            <button className="button button-outline">{t('Search')}</button>
          </form>
          <ul className="category-list team-list">
            {members.map((member) => (
              <li key={member.id} className={form.data.id === String(member.id) ? 'editing' : ''}>
                <div className="category-details">
                  <strong>
                    {member.name} {member.id === auth?.admin.id && <small>{t('(you)')}</small>}
                  </strong>
                  <span>{member.email}</span>
                  <span>
                    <b className="role-label">
                      {t(member.role.charAt(0).toUpperCase() + member.role.slice(1))}
                    </b>{' '}
                    · {member.active ? t('Active') : t('Deactivated')}
                  </span>
                </div>
                <button
                  className="icon-button"
                  aria-label={'Edit ' + member.name}
                  onClick={() => {
                    form.setData({
                      id: String(member.id),
                      name: member.name,
                      email: member.email,
                      role: member.role,
                      active: member.active === 1,
                      password: '',
                    });
                    form.clearErrors();
                    nameInput.current?.focus();
                  }}
                >
                  <Icon name="edit" />
                </button>
              </li>
            ))}
          </ul>
          <Pagination links={pagination} count={members.length} noun={t('members')} />
        </section>
        <section className="admin-card settings-card category-form">
          <h2>{editing ? t('Edit member') : t('Invite a member')}</h2>
          <p>
            {editing
              ? t('Permissions take effect on the next request.')
              : t('Create an account and share the initial password directly with your teammate.')}
          </p>
          <form
            onSubmit={(event) => {
              event.preventDefault();
              form.transform((data) => ({
                ...data,
                active: data.active ? '1' : '0',
                _token: csrfToken,
              }));
              form.post('/admin/team/save', { preserveScroll: true, onSuccess: reset });
            }}
          >
            <label htmlFor="member-name">{t('Display name')}</label>
            <input
              ref={nameInput}
              id="member-name"
              required
              maxLength={100}
              value={form.data.name}
              onChange={(event) => form.setData('name', event.target.value)}
            />
            <label htmlFor="member-email">{t('Email address')}</label>
            <input
              id="member-email"
              type="email"
              required
              maxLength={254}
              value={form.data.email}
              onChange={(event) => form.setData('email', event.target.value)}
            />
            <label htmlFor="member-role">{t('Role')}</label>
            <select
              id="member-role"
              value={form.data.role}
              onChange={(event) => form.setData('role', event.target.value)}
            >
              <option value="writer">{t('Writer')}</option>
              <option value="editor">{t('Editor')}</option>
              <option value="">{t('Choose a role')}</option>
              {roleChoices.map((role) => (
                <option key={role.key} value={role.key} disabled={!role.enabled}>
                  {t(role.name)}
                </option>
              ))}
            </select>
            <p className="field-help">
              {form.data.role === 'owner'
                ? t('Full access, including packages, settings and team management.')
                : form.data.role === 'editor'
                  ? t(
                      'Manage and publish all content, organize tags and categories, and edit navigation.',
                    )
                  : t(
                      'Write and manage personal drafts and use the media library. Publishing requires an editor.',
                    )}
            </p>
            {!ownAccount && (
              <>
                <label htmlFor="member-password">
                  {editing ? t('Reset password (optional)') : t('Initial password')}
                </label>
                <input
                  id="member-password"
                  type="password"
                  autoComplete="new-password"
                  required={!editing}
                  minLength={12}
                  maxLength={72}
                  value={form.data.password}
                  onChange={(event) => form.setData('password', event.target.value)}
                />
                {editing && (
                  <p className="field-help">
                    {t(
                      'Leave blank to keep the current password. Resetting it expires existing sessions.',
                    )}
                  </p>
                )}
              </>
            )}
            <label className="checkbox-field">
              <input
                type="checkbox"
                checked={form.data.active}
                onChange={(event) => form.setData('active', event.target.checked)}
              />{' '}
              {t('Active account')}
            </label>
            <div className="category-form-actions">
              <button className="button" disabled={form.processing}>
                {form.processing ? t('Saving…') : editing ? t('Save member') : t('Create account')}
              </button>
              {editing && (
                <button type="button" className="button button-outline" onClick={reset}>
                  {t('Cancel')}
                </button>
              )}
            </div>
          </form>
        </section>
      </div>
    </>
  );
}
Team.layout = (page: ReactNode) => <AdminLayout>{page}</AdminLayout>;
