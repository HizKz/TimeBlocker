---
name: timeblocker-release
description: Prepare and validate TimeBlocker macOS releases, including versioning, Universal archives, DMGs, and Sparkle appcasts. Use when packaging or publishing a release for this repository.
---

# TimeBlocker Release

## Release workflow

1. Read the release and update sections in `README.md`, `scripts/package-release.sh`, `TimeBlocker/Info.plist`, and the latest entries in `appcast.xml`. Treat these files as the source of truth; confirm the requested version and build number instead of guessing.
2. Inspect `git status` and existing `dist/` outputs before changing files or packaging. Preserve unrelated user changes. The packaging script deletes and recreates `dist/TimeBlocker.xcarchive`, `dist/dmg-staging`, `dist/TimeBlocker.dmg`, and `dist/TimeBlocker-rw.dmg`; check these paths before running it.
3. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in `TimeBlocker/Info.plist`. Prepare concise Japanese release notes that describe user-visible changes. Update `README.md` only when release instructions or documented behavior changed.
4. On macOS, build the Universal Release archive and DMG with `./scripts/package-release.sh`. Use a Developer ID Application identity and a configured `notarytool` profile when available (`DEVELOPER_ID_APPLICATION` and `NOTARY_PROFILE`). Without them, the script produces an ad hoc signed app; Sparkle updates can still use EdDSA signatures, but macOS Gatekeeper may block installation or launch. Explain this limitation and follow the user’s chosen distribution method.
5. For Sparkle, create `dist/updates/TimeBlocker-${VERSION}.zip` from the archived app, then run the `generate_appcast` command documented in `README.md` with the release download URL prefix and `--embed-release-notes`. Use an isolated output directory to preserve existing release artifacts; retain all previous appcast entries and their original URLs. Review the generated `appcast.xml`: the new item must match the release version/build, minimum macOS version, archive URL, signature, and notes, while prior release entries remain intact. Never print, copy into the repository, or upload the EdDSA private key; it is held in the login Keychain.
6. Publish the versioned ZIP and DMG in the same GitHub Release before updating the `main` branch appcast, so the feed never points at missing files. Publish the version/build metadata with the feed and verify the uploaded assets and live feed. Report the exact artifacts, signing/notarization status, and checks completed. If a requested release cannot be built or signed in the current environment, explain the blocker and stop before publishing.

## Publishing boundary

Packaging creates local artifacts. Uploading assets, creating a GitHub release/tag, or pushing `appcast.xml` changes a public release; do so only when the user explicitly asks to publish that release. Do not infer publication approval from a request to prepare or build a release. Before publishing, make sure the DMG and versioned Sparkle ZIP correspond to the same build and the appcast points at the intended release assets.
