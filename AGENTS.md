# Repository Guidelines

## Project Structure & Module Organization
`SwiftGMessages/` contains the app source (SwiftUI views, app state, networking/event handling, caching, logging, and preferences). Core state lives in `SwiftGMessages/GMAppModel.swift`, and related infrastructure is split into focused files such as `SwiftGMessages/GMEventStreamHandler.swift`, `SwiftGMessages/GMCacheStore.swift`, and `SwiftGMessages/GMNotifications.swift`.  
`SwiftGMessages/Assets.xcassets` stores icons/colors/image assets.  
`SwiftGMessagesTests/` contains unit tests (Swift Testing).  
`SwiftGMessagesUITests/` contains UI and launch tests (XCTest).

## Build, Test, and Development Commands
Run from repository root:

```bash
open SwiftGMessages.xcodeproj
xcodebuild -project SwiftGMessages.xcodeproj -scheme SwiftGMessages -destination 'platform=macOS' build
xcodebuild -project SwiftGMessages.xcodeproj -scheme SwiftGMessages -destination 'platform=macOS' test -only-testing:SwiftGMessagesTests
xcodebuild -project SwiftGMessages.xcodeproj -scheme SwiftGMessages -destination 'platform=macOS' test -only-testing:SwiftGMessagesUITests
```

- `open ...` opens the project in Xcode for interactive development.
- `build` validates compile/link for the shared `SwiftGMessages` scheme.
- `test` commands run unit and UI suites independently for faster iteration.

## Coding Style & Naming Conventions
Use standard Swift/Xcode formatting with 4-space indentation and one major type per file.  
Name types/protocols in `UpperCamelCase` and methods/properties in `lowerCamelCase`.  
Follow the existing domain prefix pattern (`GM...`) for app-specific types (for example `GMAppModel`, `GMLog`).  
Prefer explicit actor isolation (`@MainActor`, `actor`) for UI-bound and concurrent code.

## Testing Guidelines
Unit tests use Swift Testing (`import Testing`, `@Test`, `#expect(...)`).  
UI tests use XCTest (`XCTestCase` and `test...` methods).  
There is no enforced coverage gate yet; add regression tests for model logic, event-stream handling, cache behavior, and notification-related flows when touching those areas.

## Commit & Pull Request Guidelines
Current history favors short, direct subjects (for example `Initial Commit`, `new`). Keep commit messages concise, imperative, and scoped (example: `Add retry logic for event reconnect`).  
PRs should include a brief behavior summary, linked issue/context, test evidence (commands run), and screenshots for visible UI changes.

## Security & Configuration Tips
Never commit secrets, auth/session data, or machine-local build artifacts.  
Treat `SwiftGMessages/SwiftGMessages.entitlements` and notification/capability changes as security-sensitive; call them out explicitly in PR descriptions.
