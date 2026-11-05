import Icon from './Icon';
import { useTranslation } from '../i18n';
export default function Alert({ message, error = false }: { message?: string; error?: boolean }) {
  const { t } = useTranslation();
  if (!message) return null;
  return (
    <div className={'alert ' + (error ? 'error' : 'success')} role={error ? 'alert' : 'status'}>
      <Icon name={error ? 'alert' : 'check'} />
      {t(message)}
    </div>
  );
}
