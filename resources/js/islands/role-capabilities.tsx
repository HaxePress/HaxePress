import { useEffect, useState } from 'react';
import { createPortal } from 'react-dom';
import Alert from '../components/Alert';
import { useTranslation } from '../i18n';
import { mountReact, type IslandContext } from '../island-react';
import { hasCapability } from '../types';

interface CapabilityChoice {
  key: string;
  name: string;
  group_name: string;
  owner: string;
}

interface Props {
  choices: CapabilityChoice[];
  selected: string[];
  grantable: string[];
}

/**
 * The capability card of the role editor. The selection survives searches:
 * granted capabilities that the current results do not list are submitted
 * as hidden `grant:<key>` fields, like the visible checkboxes.
 */
function RoleCapabilities({ choices, selected: initial, grantable }: Props) {
  const { t } = useTranslation();
  const [query, setQuery] = useState('');
  const [available, setAvailable] = useState(choices);
  const [selected, setSelected] = useState(initial);
  const [lookupError, setLookupError] = useState('');
  useEffect(() => {
    if (!query) {
      setAvailable(choices);
      return;
    }
    const abort = new AbortController();
    const timer = setTimeout(async () => {
      try {
        const response = await fetch(`/admin/roles/capabilities?q=${encodeURIComponent(query)}`, {
          signal: abort.signal,
          headers: { Accept: 'application/json' },
        });
        if (!response.ok) throw new Error('Capabilities could not be loaded.');
        setAvailable((await response.json()).choices);
        setLookupError('');
      } catch (failure) {
        if (!abort.signal.aborted)
          setLookupError(
            failure instanceof Error ? failure.message : 'Capabilities could not be loaded.',
          );
      }
    }, 200);
    return () => {
      clearTimeout(timer);
      abort.abort();
    };
  }, [query, choices]);
  const editable = (key: string) => hasCapability(grantable, key);
  const listed = new Set(available.filter((choice) => editable(choice.key)).map(({ key }) => key));
  const hidden = selected.filter((key) => !listed.has(key));
  const errorTarget = document.getElementById('role-capability-error');
  return (
    <section className="admin-card settings-card">
      <h2>{t('Capabilities')}</h2>
      <label htmlFor="capability-search">{t('Search capabilities')}</label>
      <input
        id="capability-search"
        value={query}
        type="search"
        maxLength={100}
        onChange={(event) => setQuery(event.target.value)}
        placeholder={t('Search capabilities')}
      />
      <p className="field-help">
        {t('Selected capabilities: {count}', { count: selected.length })}
      </p>
      {available.map((choice) => (
        <label className="checkbox-label capability-choice" key={choice.key}>
          <input
            type="checkbox"
            name={`grant:${choice.key}`}
            value="1"
            checked={selected.includes(choice.key)}
            disabled={!editable(choice.key)}
            onChange={(event) =>
              setSelected(
                event.target.checked
                  ? [...selected, choice.key]
                  : selected.filter((key) => key !== choice.key),
              )
            }
          />
          <span>
            <strong>{t(choice.name)}</strong>
            <small>
              {t(choice.group_name)} · {choice.key}
            </small>
          </span>
        </label>
      ))}
      {hidden.map((key) => (
        <input key={key} type="hidden" name={`grant:${key}`} value="1" />
      ))}
      {errorTarget && createPortal(<Alert error message={lookupError} />, errorTarget)}
    </section>
  );
}

export function mount(element: HTMLElement, props: IslandContext & Props) {
  // Keep choices made in the server-rendered card before the island loaded.
  const boxes = element.querySelectorAll<HTMLInputElement>(
    'input[type="checkbox"][name^="grant:"]',
  );
  const selected = new Set(props.selected);
  for (const box of boxes) {
    const key = box.name.slice('grant:'.length);
    if (box.checked) selected.add(key);
    else selected.delete(key);
  }
  return mountReact(
    element,
    props,
    <RoleCapabilities
      choices={props.choices}
      selected={[...selected]}
      grantable={props.grantable}
    />,
  );
}
