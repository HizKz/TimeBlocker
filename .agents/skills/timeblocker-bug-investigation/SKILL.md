---
name: timeblocker-bug-investigation
description: Investigate TimeBlocker bugs by tracing the relevant macOS app flow, identifying a source-supported cause, and choosing focused verification. Use for diagnosing or fixing issues in this repository.
---

# TimeBlocker Bug Investigation

## Investigation workflow

1. Capture the reported behavior, expected behavior, reproduction steps, macOS version, relevant permissions, and whether Calendar or Notion is involved. If key details are missing, inspect the code and continue with explicit assumptions; ask only for details that block reproduction or change the diagnosis.
2. Inspect `git status` before editing and preserve the user's existing changes. Trace the behavior from its UI action through `AppModel` into the relevant provider, storage, timer/observer, or overlay code. Search call sites and state updates rather than assuming a file's name identifies the cause.
3. Focus investigation by subsystem:
   - Calendar data and permissions: `Providers/EventKitProvider.swift`, `Providers/EventProvider.swift`, and `App/AppModel.swift`.
   - Notion requests and token handling: `Providers/NotionTaskProvider.swift` and Notion configuration/state in `App/AppModel.swift`.
   - Notification presentation and snoozes: `Overlay/`, `Storage/NotificationHistory.swift`, and notification queue/tick logic in `App/AppModel.swift`.
   - Menu bar and settings: `MenuBar/`, `Settings/`, and `App/`.
4. Follow async boundaries, MainActor ownership, refresh cadence, persisted UserDefaults/Keychain values, and permission/error branches. Separate observed facts from hypotheses; support the proposed cause with code paths, conditions, and a concrete reproduction or log when available.
5. Match the scope to the request. For investigation-only requests, report the likely cause, evidence, impact, and next verification step without changing code. When asked to fix the bug, make the smallest relevant change and explain any behavior or data migration implications.
6. This repository has no configured automated test target. Do not invent test commands or claim automated coverage. For a code fix, choose focused manual checks that exercise the reproduction and nearby edge cases; run `xcodebuild -project TimeBlocker.xcodeproj -scheme TimeBlocker -destination 'platform=macOS' build` when a build check is useful and available. Respect requests not to run verification.

## Report

Keep the findings concise: reproduction status, root cause or ranked hypotheses, relevant file locations, changes made (if any), verification performed, and remaining uncertainty. Do not expose secrets from Keychain, configuration, logs, or diagnostic output; redact tokens and private identifiers before sharing excerpts.
