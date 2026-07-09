# CrawlBar Control Protocol

CrawlBar treats each crawler as a local CLI with a small control contract.
The canonical Go contract lives in `crawlkit/control`; CrawlBar also accepts
its legacy array-valued manifests for compatibility.

## Manifest

A crawler can be built in or represented by a manifest JSON file under
`~/.crawlbar/apps`. CrawlKit-based crawlers should expose the same payload
through `metadata --json`.

```json
{
  "schema_version": "crawlkit.control.v1",
  "id": "examplecrawl",
  "display_name": "Example Crawl",
  "description": "Local archive for Example",
  "binary": { "name": "examplecrawl" },
  "branding": { "symbol_name": "tray", "accent_color": "#2F81F7" },
  "paths": {
    "default_config": "~/.examplecrawl/config.toml",
    "config_env": "EXAMPLECRAWL_CONFIG",
    "default_database": "~/.examplecrawl/examplecrawl.db",
    "default_logs": "~/.examplecrawl/logs",
    "default_share": "~/.examplecrawl/share"
  },
  "commands": {
    "metadata": {"argv": ["examplecrawl", "metadata", "--json"], "json": true},
    "status": {"argv": ["examplecrawl", "status", "--json"], "json": true},
    "doctor": {"argv": ["examplecrawl", "doctor", "--json"], "json": true},
    "sync": {"argv": ["examplecrawl", "sync", "--json"], "json": true, "mutates": true},
    "publish": {"argv": ["examplecrawl", "publish", "--json"], "json": true, "mutates": true},
    "update": {"argv": ["examplecrawl", "update", "--json"], "json": true, "mutates": true},
    "remote-status": {"argv": ["examplecrawl", "remote", "status", "--json"], "json": true},
    "remote-archives": {"argv": ["examplecrawl", "remote", "archives", "--json"], "json": true},
    "cloud-publish": {"argv": ["examplecrawl", "cloud", "publish", "--json"], "json": true, "mutates": true}
  },
  "capabilities": ["status", "doctor", "sync", "publish", "update", "remote_archive", "cloud_publish"],
  "privacy": {
    "contains_private_messages": false,
    "exports_secrets": false,
    "local_only_scopes": []
  }
}
```

## Status Output

CrawlBar accepts varied JSON, then normalizes known fields into one status model:

- `*_count`, `counts`, or `stats` become menu counters.
- `last_sync_at`, `last_import_at`, `updated_at`, or epoch values become freshness.
- `db_path`, `database_path`, `db_bytes`, and `wal_bytes` become storage metadata.
- `share` or `sharing` becomes share/export state.
- `remote` becomes Cloudflare or other remote archive state.
- `sqlite_object` and `sqlite_bundle` become optional remote SQLite archive metadata.

Unknown fields are allowed. The app should not break when a crawler adds extra data.

The canonical `crawlkit/control.Status` envelope has:

- `app_id`, `schema_version`, `generated_at`, `state`, and `summary`.
- normalized counters as `{id,label,value}` rows.
- optional `databases` rows with `id`, `label`, `kind`, `role`, `path`,
  `is_primary`, `bytes`, `modified_at`, and optional `counts`.
- effective config/database/cache/log/share paths from `configkit`.
- freshness from `syncstate`.
- share/export state from `gitshare` and `pack`.
- remote archive state from `remote`, including endpoint, archive, ingest time,
  D1 database rows, and optional R2 SQLite object/bundle metadata.
- warnings/errors with no secret values.

## Configuration

CrawlBar file manifests can additionally include `config_options` describing
editable values and `config_sections` arranging them into native settings
groups. These are CrawlBar extensions, not fields in the current
`crawlkit/control.Manifest`. Duplicate option IDs are ignored after the first
entry so a broken external manifest cannot crash the settings UI.

Secrets must never be emitted by `metadata --json`, and config reads should
redact them unless an explicit reveal flag is provided. Longer term, crawler
CLIs should expose safe config read/write/clear commands so CrawlBar can stop
editing TOML directly.

## Actions

Canonical actions are manifest command objects containing an `argv` array.
CrawlBar also accepts its legacy array-only form and never shell-expands either.

- `status` should be fast and read-only.
- `doctor` may inspect auth/config and should avoid writes unless the crawler already defines that behavior.
- `refresh` may pull data into the local database.
- `query` should run a local read-only search or SQL-ish query. CrawlBar passes
  user query text as additional argv after the manifest command array.
- `publish`, `update`, and exporter actions are optional and should return JSON when possible.
- `remote-status` and `remote-archives` should be read-only wrappers around
  Cloudflare or equivalent remote archive status/listing commands.
- `cloud-publish` may upload rows and compressed SQLite bundle parts to a
  remote service; CLIs should keep older git snapshot publish actions separate.
- desktop-cache actions should use public names such as `desktop-cache-import`,
  `desktopcache`, or `tap`.
  Existing `wiretap` command names can stay as backward-compatible aliases, but
  new metadata should not advertise `wiretap`.

## Local Or Remote Execution

Most crawlers run locally. A manifest can also declare SSH execution when the
archive lives on another machine. For user-facing built-ins, prefer a
configurable local/remote mode so the same CrawlBar connector works on a
laptop-only setup and a server-hosted archive:

```json
{
  "id": "wacli-work",
  "display_name": "WhatsApp Work",
  "binary": { "name": "wacli" },
  "execution": {
    "kind": "local",
    "kind_config_id": "execution_mode",
    "target_config_id": "remote_target",
    "run_as_config_id": "remote_run_as",
    "remote_env_file_config_id": "remote_env_file",
    "remote_binary": "wacli"
  },
  "commands": {
    "status": ["--account", "{config:account}", "--read-only", "doctor", "--json"],
    "doctor": ["--account", "{config:account}", "--read-only", "doctor", "--json"],
    "search": ["--account", "{config:account}", "--read-only", "--json", "messages", "search"]
  },
  "config_options": [
    {
      "id": "execution_mode",
      "label": "Run location",
      "kind": "choice",
      "default_value": "local",
      "choices": ["local", "remote"]
    },
    {"id": "remote_target", "label": "SSH target", "placeholder": "user@example-host"},
    {"id": "remote_run_as", "label": "Run as user", "placeholder": "crawl"},
    {"id": "remote_env_file", "label": "Remote env file", "placeholder": "/run/service/env"},
    {"id": "account", "label": "wacli account", "default_value": "personal"}
  ]
}
```

When `kind_config_id` resolves to `local`, CrawlBar resolves and runs the
manifest binary on this Mac. When it resolves to `remote` or `ssh`, CrawlBar
resolves local `ssh`, then runs `remote_binary` on the remote host. Command
arguments are shell-quoted by CrawlBar. `{config:option_id}` placeholders are
filled from crawler settings or option defaults. Missing required placeholders
surface as setup-needed status, not as auth failures.

If `remote_env_file_config_id` is set and the referenced option has a value,
CrawlBar sources that file before executing the remote command. This supports
server-side credentials that are already hydrated into a service env file.

## Privacy

Command output is redacted before display or persistence. Logs are stored under `~/.crawlbar/logs` with private permissions.

Crawler authors should still avoid printing raw tokens, cookies, authorization headers, session IDs, or desktop cache secrets.
