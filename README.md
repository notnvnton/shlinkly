# Shlinkly

A native, open-source client for [Shlink](https://shlink.io), the self-hosted
URL shortener, for iPhone, iPad, and Mac.

[Download on the App Store](https://apps.apple.com/app/shlinkly/id6780160853) · [Download for Mac](https://github.com/notnvnton/shlinkly/releases/latest/download/Shlinkly.dmg)

Shlinkly connects to your own Shlink server and lets you manage every short link,
campaign, and click from one app that feels right at home on Apple platforms.
Your API keys stay under your control: on-device or synced via iCloud Keychain,
end-to-end encrypted.

## Features

- Browse all your short links with search, tags, and sorting
- Create links in seconds: custom slugs, tags, UTM forwarding, expiry dates, visit limits
- Readable analytics: visits per day, week or month, people and bots in one chart, countries, and traffic sources
- QR codes for any link, made on your device as PNG or SVG
- Shorten straight from the share sheet in any app
- Find your links in Spotlight; widget, Shortcuts and Siri on iPhone and iPad
- On Mac: generate a short link from your clipboard right in the menu bar
- Connect multiple Shlink servers and switch between them
- Keys stored on-device or synced via iCloud Keychain, never sent anywhere else

## Requirements

- A running [Shlink](https://shlink.io) server and an API key (tested with Shlink 5.x)
- iOS / iPadOS 17.6+ or macOS 14+

## Download

- iPhone and iPad: [App Store](https://apps.apple.com/app/shlinkly/id6780160853)
- Mac: [Shlinkly.dmg](https://github.com/notnvnton/shlinkly/releases/latest/download/Shlinkly.dmg), notarized, with automatic updates

## Building from source

1. Clone the repo and open `Shlinkly.xcodeproj` in Xcode 26+.
2. Select your own Apple Developer team under Signing & Capabilities.
3. Build and run on iOS or macOS.

Servers and API keys are stored in the Keychain at runtime: no config files needed.

## Tech

Native SwiftUI, multiplatform (iOS + macOS, not Mac Catalyst). State via
`@Observable`; all models, the API client (`actor ShlinkClient`), and stores live
in a UI-free `ShlinklyCore` module. Typed-route navigation: `NavigationStack` on
iOS, a three-column `NavigationSplitView` on macOS.

## Contributing

Issues and pull requests are welcome. For larger changes, open an issue first.

## Support

If Shlinkly is useful to you, you can [buy me a coffee](https://www.buymeacoffee.com/notnvnton).

## License

[MIT](LICENSE) © 2026 Anton Hodge
