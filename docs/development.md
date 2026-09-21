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

The packaging script asks SwiftPM for its binary output directory, so both native SwiftPM and SwiftBuild layouts work. Pass `--arch arm64`, `--arch x86_64`, or `--arch universal` to select an architecture explicitly. Without an argument, it builds for the current Mac; `CRAWLBAR_UNIVERSAL=1` still builds both architectures. The packaging script writes `dist/CrawlBar.app`. Local and CI packages use ad-hoc signing and do not need release credentials.

## Official artifacts

The packaged app bundle version comes from `version.env`. Release notes live in [CHANGELOG.md](../CHANGELOG.md).

`Scripts/package_release.sh` builds the official universal, hardened app, then notarizes, staples, and verifies it. Official packaging fails closed unless it uses the OpenClaw Foundation Developer ID identity. Runtime keychain and notarization-profile locators belong in the ignored `.mac-release.local.env`, never in committed configuration.

Maintainers can also build smaller architecture-specific artifacts with `Scripts/package_release.sh --arch arm64` and `Scripts/package_release.sh --arch x86_64`. The universal archive keeps its `CrawlBar-vVERSION-macos.zip` name; thin archives add `-arm64` or `-x86_64` before `.zip`. Each archive has a matching `.sha256` file. Every variant includes the app, CLI helper, and resources and receives its own signing and notarization checks.

`Scripts/verify_release.sh` checks the completed release artifact. Pass the matching `--arch arm64` or `--arch x86_64` for a thin archive; verification requires exactly that architecture in both executables. Its default still requires the universal pair. Publishing tags or release artifacts is a separate maintainer action and is not part of local packaging.

## Homebrew formula

After publishing, download the public archives and their `.sha256` files into a clean directory. Run `Scripts/verify_release.sh --require-notarized` on each archive with the matching `--arch` before generating the formula:

```sh
Scripts/render_homebrew_formula.sh 0.5.1 --artifacts <verified-directory> > crawlbar.rb
```

The renderer checks each checksum against its archive. A complete universal, arm64, and x86_64 set generates architecture-specific downloads; a directory containing only the universal pair generates a universal formula for older releases. Any incomplete thin set or checksum mismatch fails. `Scripts/render_homebrew_formula.sh <version> <sha256>` also renders a universal formula. Rendering does not replace signature and notarization verification or publish anything.

Add the generated formula to `openclaw/homebrew-tap` only after the public artifacts pass verification. On clean Apple Silicon and Intel hosts, run `brew audit --strict openclaw/tap/crawlbar`, `brew install --build-from-source openclaw/tap/crawlbar`, and `brew test openclaw/tap/crawlbar`. The formula installs the signed app unchanged, writes its CLI wrapper outside the app, and checks both executable architectures, the Foundation signature, hardened runtime, Gatekeeper, and stapling.
