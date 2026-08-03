# CrawlBar CLI reference

The packaged app installs its helper as `crawlbar`. In a source checkout, use `swift run crawlbarctl` in place of `crawlbar`; the different SwiftPM name avoids a collision with the `CrawlBar` app binary on case-insensitive macOS filesystems.

Run `crawlbar --help` for the authoritative command list provided by your installed version.

## Discovery and status

```text
crawlbar apps [--json]
crawlbar metadata [--app <id>] [--json] [--diagnostics]
crawlbar status [--app <id|all>] [--json]
crawlbar logs [--json]
```

`apps` reports every discovered manifest and whether its executable is available. `metadata` prints the normalized manifest contract. `status` runs the read-only status command exposed by one crawler or all crawlers. `logs` lists recent redacted action-log paths.

Built-in manifests use these IDs and executable names:

| Source | CrawlBar ID | Executable |
|---|---|---|
| GitHub | `gitcrawl` | `gitcrawl` |
| Slack | `slacrawl` | `slacrawl` |
| Discord | `discrawl` | `discrawl` |
| Telegram | `telecrawl` | `telecrawl` |
| iMessage | `imsgcrawl` | `imsgcrawl` |
| Apple Photos | `photoscrawl` | `photoscrawl` |
| WeChat | `weicrawl` | `weicrawl` |
| Notion | `notcrawl` | `notcrawl` |
| Google | `gogcli` | `gog` |
| WhatsApp | `wacli` | `wacli` |
| X | `birdclaw` | `bird` |
| Granola | `graincrawl` | `graincrawl` |

## Crawler operations

```text
crawlbar doctor --app <id> [--json]
crawlbar refresh --app <id> [--json]
crawlbar query --app <id|all> [--json] -- <text-or-sql>
crawlbar action <action-id> --app <id> [--json]
crawlbar install --app <id> [--json]
crawlbar backup --app <id> [--json]
crawlbar folder --app <id> [--json]
```

Available actions come from each crawler manifest. `query` passes every argument after `--` to the crawler without shell expansion. `backup` copies the crawler's reported primary database into CrawlBar's backup location, and `folder` opens the reported data folder.

Examples:

```sh
crawlbar status --app all --json
crawlbar query --app slacrawl -- 'select count(*) from messages;'
crawlbar action cloud-publish --app discrawl --json
```

Commands that contact a source, mutate an archive, publish data, or use SSH require the corresponding crawler's configuration and credentials.

## Configuration

```text
crawlbar config path
crawlbar config validate
crawlbar config init
crawlbar config get --app <id> [--key <id>] [--json] [--reveal]
crawlbar config set --app <id> --key <id> --value <value> [--json]
```

The main configuration file is `~/.crawlbar/config.json`. External manifests live under `~/.crawlbar/apps`, and redacted action logs live under `~/.crawlbar/logs`.

Secret configuration values are hidden by default. Use `--reveal` only in a private terminal when the raw value is explicitly required.

## Development binary overrides

Register a locally built crawler without replacing a Homebrew or system binary:

```text
crawlbar dev register --app <id> --binary <path> [--json]
crawlbar dev unregister --app <id> [--json]
crawlbar dev list [--json]
```

Registration enables the crawler and records the explicit binary path in CrawlBar's configuration. Unregistering removes that override but leaves the crawler's other settings intact.

## JSON output

Commands with `--json` emit machine-readable output and keep diagnostics on standard error. CrawlBar redacts known secret values from crawler command output before returning or persisting it.
