# Development and packaging

`Package.swift` requires Swift tools 6.1 and targets macOS 14 or newer.

## Build and test

```sh
swift build
swift run crawlbar-selftest
swift run crawlbarctl apps --json
swift run crawlbarctl metadata --json
swift run crawlbarctl config validate
python3 Scripts/test_cli.py "$(swift build --show-bin-path)/crawlbarctl"
```

SwiftPM names the development CLI `crawlbarctl` to avoid colliding with the `CrawlBar` app binary on case-insensitive macOS filesystems. Packaged and Homebrew installations expose the helper as `crawlbar`.

CI runs the build, executable self-test, CLI smoke, and packaging checks with Xcode 16.3 on macOS 15 and Xcode 26.6 on macOS 26. Xcode 16.3 verifies the Swift 6.1 floor; the newer toolchain checks forward compatibility. Select a local Xcode with `DEVELOPER_DIR` when testing a specific compiler.

## Package the app

```sh
Scripts/package_app.sh
codesign --verify --deep --strict --verbose=2 dist/CrawlBar.app
dist/CrawlBar.app/Contents/Helpers/crawlbar config validate
```

The packaging script asks SwiftPM for its binary output directory, so both native SwiftPM and SwiftBuild layouts work. Set `CRAWLBAR_UNIVERSAL=1` to build both arm64 and x86_64 locally. The packaging script writes `dist/CrawlBar.app`. Local and CI packages use ad-hoc signing and do not need release credentials.

## Official artifacts

The packaged app bundle version comes from `version.env`. Release notes live in [CHANGELOG.md](../CHANGELOG.md).

`Scripts/package_release.sh` builds the official universal, hardened app, then notarizes, staples, and verifies it. Official packaging fails closed unless it uses the OpenClaw Foundation Developer ID identity. Runtime keychain and notarization-profile locators belong in the ignored `.mac-release.local.env`, never in committed configuration.

`Scripts/verify_release.sh` checks the completed release artifact. Publishing tags or release artifacts is a separate maintainer action and is not part of local packaging.
