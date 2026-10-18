# Releasing gaugent

Distribution uses GitHub Releases for universal macOS 14+ DMGs and an appcast on `main` for Sparkle updates. Publication is manual. CI verifies tests and local packaging; it has no release credentials and never publishes a release.

## One-time setup

- Install a **Developer ID Application** identity in the release Mac's keychain. Use `security find-identity -v -p codesigning` to find its name.
- Store notarization credentials interactively with `xcrun notarytool store-credentials gaugent-notary`. Use your own Apple developer team and account. Do not put passwords, certificates, API keys, or private signing keys in the repository or release notes.
- Run `swift package resolve`, then `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account gaugent` once. This uses a separate keychain account from Gitacre. Back up the private key securely outside this repository using the tool's export option. Keep the public feed URL available for the lifetime of shipped installs.
- Export only the public half for packaging:

```sh
export GAUGENT_SPARKLE_PUBLIC_KEY="$(.build/artifacts/sparkle/Sparkle/bin/generate_keys --account gaugent -p)"
export GAUGENT_SIGNING_IDENTITY="Developer ID Application: YOUR NAME (TEAM ID)"
```

The default feed is `https://raw.githubusercontent.com/shivamx96/gaugent/main/website/appcast.xml`. Confirm it is publicly accessible before shipping. `GAUGENT_APPCAST_URL`, `GAUGENT_APPCAST_PATH`, `GAUGENT_NOTARY_PROFILE`, and `GAUGENT_SPARKLE_KEY_ACCOUNT` can override their defaults. Existing installs keep their embedded feed URL; preserve it or redirect it when moving hosting.

## Prepare a candidate

Start from a clean, up-to-date `main`. Choose a marketing version and a positive integer build number greater than every published build. Both `0.1.0` and `0.1.0-beta.1` are accepted. The numeric marketing version goes in `CFBundleShortVersionString`, the full label in `GaugentReleaseLabel`, and the build number in `CFBundleVersion`. Sparkle compares the build number.

1. Update `Support/Info.plist` version/build and the fallback version in `Sources/GaugentCore` if applicable. Copy `release-notes/TEMPLATE.md` to a file named for the release label and replace its placeholders.
2. Run `swift test` and `python3 -m unittest discover -s Tests`.
3. Run `scripts/release.sh 0.1.0-beta.1 1`, substituting the chosen version/build.

The script validates version ordering and the update key before compilation, verifies the universal binary, notarizes and staples the app and DMG, assesses Gatekeeper acceptance, writes a checksum, signs and verifies the final DMG with Sparkle, and updates the local appcast. The feed contains archive signatures; the XML itself is not signed. Inspect all generated changes before publication.

Do not modify a DMG after signing it. If a candidate fails, inspect the failure and explicitly remove its generated DMG and checksum before rebuilding. The script refuses to overwrite candidates and the appcast refuses duplicate or older builds. If an unpublished feed entry was generated during a failed attempt, restore that local entry before retrying; never remove an already-published entry to reuse its build number.

## Local pipeline verification

No release credentials are required for this command:

```sh
GAUGENT_SIGNING_IDENTITY=- GAUGENT_SKIP_NOTARIZATION=1 \
  scripts/release.sh 0.0.0-localtest 1
(cd dist && shasum -a 256 -c gaugent-0.0.0-localtest-local.dmg.sha256)
```

The `-local.dmg` is ad hoc signed, has no configured updater, and never changes the appcast. It is only for packaging tests and must not be distributed as a public release.

## Acceptance before publication

- Mount the signed DMG, drag gaugent into Applications, eject it, and launch from Applications on a clean macOS account. Confirm Gatekeeper acceptance without bypassing quarantine.
- Verify the menu-bar panel, CLI discovery/sign-in recovery, settings, launch at login, and diagnostics. Confirm both architecture slices with `lipo -archs build/gaugent.app/Contents/MacOS/Gaugent`; exercise Intel hardware when available, since cross-compilation alone does not verify execution there.
- Test upgrading between two Developer ID-signed/notarized builds using a separate HTTPS test feed (`GAUGENT_APPCAST_URL` and `GAUGENT_APPCAST_PATH`). Verify manual check, automatic-check preference persistence, background download preference, Later, download failure/retry, install/relaunch, and preservation of provider/settings data. Never put test builds in the public feed.
- Check release notes, minimum macOS version, checksum, and the appcast's version, URL, length, and signature. Use `.build/artifacts/sparkle/Sparkle/bin/sign_update --account gaugent --verify dist/FILE.dmg SIGNATURE` to verify the enclosure signature.

A successful local build does not satisfy signing, clean-install, or live-upgrade acceptance. The first updater-enabled build must be installed manually; earlier builds cannot bootstrap themselves into Sparkle.

## Publish assets, then the feed

Use a release branch for version metadata and notes. Keep the generated appcast change out of the initial source release commit. After the source release commit is merged into main, tag that exact reviewed commit. Build artifacts must correspond to that source revision; do not tag a different implementation.

Example for a prerelease (substitute the label throughout):

```sh
git tag -a v0.1.0-beta.1 -m 'gaugent 0.1.0-beta.1'
git push origin v0.1.0-beta.1
gh release create v0.1.0-beta.1 \
  dist/gaugent-0.1.0-beta.1.dmg \
  dist/gaugent-0.1.0-beta.1.dmg.sha256 \
  --verify-tag --draft --prerelease \
  --title 'gaugent 0.1.0-beta.1' \
  --notes-file release-notes/0.1.0-beta.1.md
```

Review the draft and its assets, then publish it with `gh release edit v0.1.0-beta.1 --draft=false`. For a stable release, omit `--prerelease` when creating the draft. Download the public DMG and checksum into a new temporary directory and run `shasum -a 256 -c FILE.dmg.sha256`. Confirm the public asset URL works without authentication.

Only then open and merge a PR containing `website/appcast.xml`. That merge advertises the update to installed users. Fetch the public raw feed and verify its enclosure resolves to the asset just tested. The download site discovers published releases automatically; redeploy it when static content changes.

The initial feed is empty. A release must not be advertised until it exists. The default feed serves one release stream, including betas; do not publish experimental builds there merely because GitHub labels them prereleases.

## Recovery

If a release is faulty, stop advertising it by reverting its feed entry and fix the website's selection if necessary. Removing a feed entry does not downgrade users who already installed it. Ship a correction with a higher build number, even if restoring older application behavior. Keep old assets/feed URLs available for existing installations. Never replace the bytes of a published signed artifact under the same URL.

## Merging the distribution stack

Merge the five PRs from bottom to top. After each merge, retarget the next PR to main and ensure its diff contains only its layer. If squash merging changes the ancestry, rebase the remaining branches before merging; otherwise earlier commits can reappear in later PR diffs. Re-run checks after each rebase. These PRs configure distribution; they do not themselves publish a public release.
