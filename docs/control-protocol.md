# CrawlBar Control Protocol

CrawlBar treats each crawler as a local CLI with a small control contract.
Today that contract lives in CrawlBar manifests and adapters. The cleaner
long-term home is `crawlkit`, because the Go CLIs already share config,
status, output, desktop-cache, pack, and git-share infrastructure there.

## Manifest

A crawler can be built in or represented by a manifest JSON file under
`~/.crawlbar/apps`. Once `crawlkit` grows a control package, each crawler should
also expose the same payload through `metadata --json`.

```json
{
  "schema_version": 1,
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
    "metadata": ["metadata", "--json"],
    "status": ["status", "--json"],
    "doctor": ["doctor", "--json"],
    "refresh": ["sync", "--json"],
    "publish": ["publish", "--json"],
    "update": ["update", "--json"],
    "remote-status": ["remote", "status", "--json"],
    "remote-archives": ["remote", "archives", "--json"],
    "cloud-publish": ["cloud", "publish", "--json"]
  },
  "capabilities": ["status", "doctor", "refresh", "publish", "update", "remote_archive", "cloud_publish"],
  "config_options": [
    {
      "id": "api_token",
      "label": "API token",
      "kind": "secret",
      "env_var": "EXAMPLECRAWL_TOKEN",
      "config_key": "example.token"
    },
    {
      "id": "embedding_model",
      "label": "Embedding model",
      "kind": "choice",
      "default_value": "text-embedding-3-small",
      "choices": ["text-embedding-3-small", "text-embedding-3-large"],
      "env_var": "OPENAI_EMBEDDING_MODEL",
      "config_key": "embeddings.model"
    }
  ],
  "config_sections": [
    {
      "id": "access",
      "title": "Example Access",
      "option_ids": ["api_token"]
    },
    {
      "id": "ai",
      "title": "Embeddings",
      "option_ids": ["embedding_model"]
    }
  ],
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

The preferred future shape is a `crawlkit`-owned status envelope with:

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

`config_options` describe editable values. `config_sections` only arrange those
fields into native settings groups. Duplicate option IDs are ignored after the
first entry so a broken external manifest cannot crash the settings UI.

Secrets must never be emitted by `metadata --json`, and config reads should
redact them unless an explicit reveal flag is provided. Longer term, crawler
CLIs should expose safe config read/write/clear commands so CrawlBar can stop
editing TOML directly.

## Actions

Actions are manifest command arrays. CrawlBar does not shell-expand them.

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
