# TimeBlocker

TimeBlocker is a macOS menu bar app that watches selected Calendar calendars and displays a translucent full-screen event panel when events begin.

## Requirements

- macOS 14 or newer
- Xcode 15 or newer

## Build

Open `TimeBlocker.xcodeproj` in Xcode and run the `TimeBlocker` scheme. On first launch, allow Full Access to Calendar so the app can read event times. You can change monitored calendars in **Settings → Calendar**.

## Features

- Reads events from selected Calendar calendars and shows matching calendar colors in the menu bar, settings, and event panel.
- Shows a translucent panel across all displays or only the main display. Events with the same start time appear together.
- Opens event links from the panel, or snoozes the displayed events for 5, 10, or 15 minutes.
- Persists snoozes across app restarts and skips events that have ended, been deleted, or changed before the reminder.
- Lets the user skip the displayed events. Handled events are stored locally to prevent duplicate notifications.
- Provides quick event creation with configurable default duration and calendar.
- Supports configurable recovery notification grace periods after Mac wake or app launch.

All calendar access and notification history remain local to the Mac. Notion integration and login-at-startup are not implemented yet.

## License

TimeBlocker is distributed under the MIT License. See [LICENSE](LICENSE) for details.
