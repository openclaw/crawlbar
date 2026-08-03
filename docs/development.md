# Development and packaging

`Package.swift` requires Swift tools 6.1 and targets macOS 14 or newer.

## Build and test

```sh
swift build
swift run crawlbar-selftest
swift run crawlbarctl apps --json
swift run crawlbarctl metadata --json
swift run crawlbarctl config validate
```

SwiftPM names the development CLI `crawlbarctl` to avoid colliding with the `CrawlBar` app binary on case-insensitive macOS filesystems. Packaged and Homebrew installations expose the helper as `crawlbar`.

## Package the app

```sh
Scripts/package_app.sh
codesign --verify --deep --strict --verbose=2 dist/CrawlBar.app
dist/CrawlBar.app/Contents/Helpers/crawlbar config validate
```

The packaging script writes `dist/CrawlBar.app`. Local and CI packages use ad-hoc signing and do not need release credentials.

## Official artifacts

The packaged app bundle version comes from `version.env`. Release notes live in [CHANGELOG.md](../CHANGELOG.md).

`Scripts/package_release.sh` builds the official universal, hardened app, then notarizes, staples, and verifies it. Official packaging fails closed unless it uses the OpenClaw Foundation Developer ID identity. Runtime keychain and notarization-profile locators belong in the ignored `.mac-release.local.env`, never in committed configuration.

`Scripts/verify_release.sh` checks the completed release artifact. Publishing tags or release artifacts is a separate maintainer action and is not part of local packaging.
