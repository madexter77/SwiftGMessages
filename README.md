# SwiftGMessages

A native macOS and iOS client for Google Messages. Pair your Android phone and access your text conversations from your Mac or iPad with full RCS support.

## Features

- **Phone Pairing** - Scan a QR code to link your Android phone
- **Real-Time Sync** - Conversations and messages stay up to date via live event stream
- **Send & Receive** - Text messages, media attachments, and voice recordings
- **Reactions & Read Receipts** - React to messages, see typing indicators and read status
- **Push Notifications** - Configurable push notification support with custom backend endpoint
- **Background Sync** - Scheduled polling keeps conversations fresh when the app is in the background
- **Conversation Management** - Search, archive, mute, and organize conversations
- **Link Previews** - Automatic link metadata fetching and display
- **Multi-Platform** - Runs natively on macOS, iOS, and visionOS

## Requirements

- macOS 26.1+ / iOS 26.1+ / visionOS 26.1+
- Xcode 16+
- An Android phone with Google Messages installed

## Getting Started

### Build from Source

```bash
git clone https://github.com/mweinbach/SwiftGMessages.git
cd SwiftGMessages
open SwiftGMessages.xcodeproj
```

Build and run the `SwiftGMessages` scheme targeting your platform of choice.

### Pairing

1. Open the app on your Mac or iPad
2. On your Android phone, open Google Messages and go to **Device pairing**
3. Scan the QR code displayed in the app
4. Your conversations will sync automatically

## Architecture

The app follows an **MVVM pattern with actor-based concurrency**:

```
App/                 Entry point, scene setup
Models/              App state (GMAppModel), preferences, push config
Services/            Event stream handler, disk/memory cache, notifications
Utilities/           Logging, date parsing, styling
Views/
  Messages/          Conversation list, message thread, composer
  Pairing/           QR code pairing flow
  Settings/          Notification, sync, and account settings
```

### Key Components

| Component | Role |
|---|---|
| `GMAppModel` | Central state machine - manages conversations, messages, connection lifecycle |
| `GMEventStreamHandler` | Bridges LibGM callbacks into an `AsyncStream` for reactive event handling |
| `GMCacheStore` | Protobuf-serialized disk + in-memory cache for offline access |
| `GMNotifications` | Local notification scheduling and management |
| `GMLiveClient` | Actor wrapper over the LibGM protocol client |

### Dependencies

- [swift-gmessages](https://github.com/mweinbach/swift-gmessages) - Google Messages protocol client library (LibGM + GMProto)
- [SwiftProtobuf](https://github.com/apple/swift-protobuf) - Protocol Buffer runtime

## Building & Testing

```bash
# Build for macOS
xcodebuild -project SwiftGMessages.xcodeproj -scheme SwiftGMessages \
  -destination 'platform=macOS' build

# Run unit tests
xcodebuild -project SwiftGMessages.xcodeproj -scheme SwiftGMessages \
  -destination 'platform=macOS' test -only-testing:SwiftGMessagesTests

# Run UI tests
xcodebuild -project SwiftGMessages.xcodeproj -scheme SwiftGMessages \
  -destination 'platform=macOS' test -only-testing:SwiftGMessagesUITests
```

## Permissions

The app requests the following entitlements:

| Permission | Reason |
|---|---|
| Network | Communicate with Google Messages servers |
| Microphone | Record voice messages |
| File Access (read-only) | Attach files from the file picker |
| Notifications | Deliver incoming message alerts |

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
