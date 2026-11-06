export function activate({ root, t }) {
  const article = root.querySelector('.content-prose');
  if (!article) return;
  const progress = document.createElement('div');
  progress.className = 'reading-companion-progress';
  progress.setAttribute('role', 'progressbar');
  progress.setAttribute('aria-label', t('Reading progress'));
  progress.setAttribute('aria-valuemin', '0');
  progress.setAttribute('aria-valuemax', '100');
  root.append(progress);
  function update() {
    const bounds = article.getBoundingClientRect();
    const distance = Math.max(1, bounds.height - window.innerHeight);
    const value = Math.round(Math.max(0, Math.min(1, -bounds.top / distance)) * 100);
    progress.style.width = `${value}%`;
    progress.setAttribute('aria-valuenow', String(value));
  }
  window.addEventListener('scroll', update, { passive: true });
  window.addEventListener('resize', update);
  update();
  return () => {
    window.removeEventListener('scroll', update);
    window.removeEventListener('resize', update);
    progress.remove();
  };
}
