# Repository Guidelines

## Project Structure

TimeBlocker is a Swift 5 macOS menu bar app targeting macOS 14+. Open `TimeBlocker.xcodeproj` and use the `TimeBlocker` scheme. App code is under `TimeBlocker/`, organized by feature: `App/`, `Domain/`, `MenuBar/`, `Overlay/`, `Providers/`, `Settings/`, `Storage/`, and `Utilities/`. Assets live in `TimeBlocker/Assets.xcassets/`; app permissions and metadata are in `TimeBlocker/TimeBlocker.entitlements` and `TimeBlocker/Info.plist`. Release packaging is handled by `scripts/package-release.sh`; DMG artwork is in `assets/`. There is currently no separate test directory or test target.

## Build and Development

- `open TimeBlocker.xcodeproj` opens the project in Xcode; select the `TimeBlocker` scheme and run it to launch the menu bar app.
- `xcodebuild -project TimeBlocker.xcodeproj -scheme TimeBlocker -destination 'platform=macOS' build` builds from the command line.
- `./scripts/package-release.sh` creates a release app archive and `dist/TimeBlocker.dmg`. For public distribution, configure the signing and notarization variables documented in `README.md`.

## Code Style

Follow the surrounding Swift style: four-space indentation, descriptive `UpperCamelCase` type names, and `lowerCamelCase` properties and functions. Keep code in the directory matching its responsibility, and prefer small, focused changes. No formatter or linter configuration is present; match nearby files and keep Xcode project settings consistent with the macOS 14 deployment target.

## Testing

No automated test target is currently configured. For code changes, build the app with the command above and manually verify the affected flow in macOS, including permission-dependent Calendar behavior or Notion connectivity when relevant. Do not claim automated tests passed unless a test target is added and run.

## Commits and Pull Requests

Recent commits use short, imperative summaries (for example, `Add search for today's events`). Follow that pattern and keep each commit focused. Pull requests should explain the user-visible change, list manual verification performed, link related issues, and include screenshots or a short recording for UI changes. Call out changes to permissions, release packaging, or `appcast.xml` explicitly.

## Security and Configuration

Never commit Notion integration tokens, signing credentials, notarization secrets, or update-signing private keys. The app stores the Notion token in macOS Keychain; preserve that behavior. Keep release and update metadata aligned with the version being shipped.
