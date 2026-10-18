# gaugent download website

Static HTML/CSS/JavaScript with native app screenshots using synthetic data. No build step, analytics, cookies, or authentication. The only external request is to the public GitHub Releases API.

## Preview and test

```sh
python3 -m http.server 8080 --directory website
node --test website/release.test.mjs
```

Open http://localhost:8080. Test desktop and narrow layouts, keyboard focus, and release discovery. Published prereleases are eligible. Draft releases, missing DMGs, and `-local.dmg` assets are ignored. The page selects the most recently published eligible release and retains its GitHub Releases link on timeout, rate limiting, or network failure. It never needs a GitHub token.

**The repository is currently private.** The public API/feed and unauthenticated release downloads therefore do not work yet. Before deploying for public use, make distribution accessible through a public repository or configure public hosting for assets and the feed; update the release URL configuration and site endpoint together. Changing repository visibility is a separate owner decision. Do not embed private-repository tokens in the site or app.

## Container deployment

```sh
docker build -t gaugent-website:local website
docker run --rm --read-only --tmpfs /tmp --cap-drop ALL \
  --security-opt no-new-privileges -p 127.0.0.1:8080:8080 gaugent-website:local
```

Or run `docker compose -f website/compose.yaml up --build -d`. Set `PORT` to choose a different local port. NGINX runs as an unprivileged user, serves `/healthz`, and applies a Content Security Policy. Put an HTTPS reverse proxy in front of the loopback binding for deployment. The base image is pinned by digest; update it deliberately and re-run container checks. CI builds the container and verifies its health, asset MIME types, and update feed.

The container includes `appcast.xml`, but released apps default to the raw GitHub feed. Website deployment does not publish that GitHub feed; merging the feed PR does. Keep the configured feed URL alive for installed apps. See [the release runbook](../docs/RELEASING.md).

The site has not been publicly deployed by this change. Update screenshots through `GAUGENT_PREVIEW_DIR=/tmp/gaugent-previews swift test --filter PanelPreviewTests`, copying fixture renders only. Never publish screenshots containing real account details.

## Brand assets

The native app, ICNS bundle, website logo, and PNG favicons share `Sources/Gaugent/BrandArtwork.swift`. Regenerate with:

```sh
scripts/generate-icons.sh /tmp/gaugent.icns website/assets
```

The 16/32px versions omit calibration details for legibility. `assets/favicon.svg` mirrors that small-size geometry as a scalable browser fallback; keep its paths and colors aligned when changing the artwork. The menu-bar status needle remains driven by the current allowance.
