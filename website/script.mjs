import { selectRelease } from './releases.mjs';

fetch('https://api.github.com/repos/shivamx96/gaugent/releases?per_page=30', {
  headers: { Accept: 'application/vnd.github+json' }, signal: AbortSignal.timeout(8000)
}).then(response => {
  if (!response.ok) throw new Error('Releases unavailable');
  return response.json();
}).then(releases => {
  const release = selectRelease(releases);
  if (!release) {
    if (!document.querySelector('.release-link[href]')) {
      document.querySelector('#release-note').textContent = 'First public release coming soon.';
    }
    return;
  }
  document.querySelectorAll('.release-link').forEach(link => {
    link.href = release.url;
    link.textContent = link.dataset.downloadLabel || 'Download for macOS ↓';
    link.removeAttribute('aria-disabled');
    link.removeAttribute('tabindex');
  });
  document.querySelector('#release-note').textContent = `${release.version}${release.prerelease ? ' · Prerelease' : ''} · Direct DMG download`;
}).catch(() => {
  // Keep any published direct-DMG fallback intact if the API is unavailable.
  // Before the first release, buttons remain visibly unavailable.
});
