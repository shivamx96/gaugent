import { selectRelease } from './releases.mjs';

fetch('https://api.github.com/repos/shivamx96/gaugent/releases?per_page=30', {
  headers: { Accept: 'application/vnd.github+json' }, signal: AbortSignal.timeout(8000)
}).then(response => {
  if (!response.ok) throw new Error('Releases unavailable');
  return response.json();
}).then(releases => {
  const release = selectRelease(releases);
  if (!release) {
    document.querySelector('#release-note').textContent = 'No public download yet. Follow releases on GitHub.';
    return;
  }
  document.querySelectorAll('.release-link').forEach(link => {
    link.href = release.url;
    link.textContent = 'Download for macOS ↓';
  });
  document.querySelector('#release-note').textContent = `${release.version}${release.prerelease ? ' · Prerelease' : ''} · Direct DMG download`;
}).catch(() => {
  // Keep the real GitHub Releases fallback usable offline, without JS, or when rate-limited.
});
