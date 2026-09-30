# 03 - File logs -> Loki (native OTLP endpoint)

Tails application log files, routes JSON lines to a JSON parser and plain-text lines to a severity regex, persists read offsets on disk, and ships logs to Loki 3.x through its native OTLP endpoint. The outcome is structured logs in Loki with correct severity, JSON fields as attributes, a `service_name` stream label, and no duplicates or gaps after collector restarts.

## When to use

- Applications write logs to files (JSON or plain text) and you run Loki 3.0 or newer.
- You are migrating off Promtail or the removed contrib `loki` exporter.
- You need multi-tenant Loki/GEL (`X-Scope-OrgID`).

Not for: Loki 2.x (no `/otlp` endpoint), or container stdout collection in Kubernetes (needs container log parsing and k8s metadata).

## How it works

```
file_log (router -> json_parser | regex_parser, file_storage checkpoints)
  -> memory_limiter -> resource_detection -> resource/service -> batch
  -> otlp_http/loki (X-Scope-OrgID, gzip, retry, sending_queue)
```

- The `router` operator sends lines starting with `{` to `json_parser` (severity from `attributes.level`) and everything else to `regex_parser`, which extracts `trace|debug|info|warn|warning|error|fatal|critical` case-insensitively. `on_error: send_quiet` lets lines without a level through unchanged.
- `file_storage/checkpoints` stores file offsets, so a restart resumes exactly where it stopped.
- `memory_limiter` first; `resource_detection` adds `host.name`.
- `resource/service` inserts `service.name` (only if missing). Loki turns it into the `service_name` stream label.
- `batch` last, then OTLP/HTTP; the exporter appends `/v1/logs` to the endpoint.

## Quickstart

1. `cp .env.example .env`
2. Edit `.env`: `LOKI_OTLP_ENDPOINT` (e.g. `http://loki:3100/otlp`), `LOKI_TENANT_ID`, `LOG_SERVICE_NAME`, and `APP_LOG_DIR` (host directory with `*.log` files).
3. Create the checkpoint volume once: `mkdir -p data && sudo chown 10001:10001 data`
4. `docker compose up -d`
5. Verify: `docker compose logs -f otelcol` (look for `Everything is ready` and no export errors), then query Loki: `{service_name="my-app"}`. The health port is not published by this compose file.

Validate before deploying:

```
docker run --rm -v "$PWD:/cfg:ro" -e LOKI_OTLP_ENDPOINT=http://loki:3100/otlp \
  otel/opentelemetry-collector-contrib:0.161.0 validate --config=/cfg/config.yaml
```

Run the binary / other platforms: `LOKI_OTLP_ENDPOINT=http://loki:3100/otlp LOG_INCLUDE_GLOB='/var/log/my-app/*.log' OTEL_STORAGE_DIR=/var/lib/otelcol/file_storage otelcol-contrib --config=config.yaml`

## Configuration (environment variables)

| Variable | Default | Required | Purpose |
|---|---|---|---|
| `LOKI_OTLP_ENDPOINT` | `http://loki:3100/otlp` | No (compose requires it) | Loki OTLP base URL; `/v1/logs` is appended |
| `LOKI_TENANT_ID` | `anonymous` | No | Sent as `X-Scope-OrgID` (multi-tenant Loki/GEL) |
| `LOG_INCLUDE_GLOB` | `/var/log/app/*.log` | No | Files to tail |
| `LOG_START_AT` | `end` | No | `beginning` only for a one-off backfill |
| `LOG_SERVICE_NAME` | `unknown_service` | No | `service.name` if none is set |
| `OTEL_STORAGE_DIR` | `/var/lib/otelcol/file_storage` | No | Checkpoint directory; must be writable and persistent |
| `OTEL_HEALTH_ADDR` | `localhost` | No | health_check bind address |
| `OTEL_TELEMETRY_ADDR` | `localhost` | No | Bind address of internal `/metrics` on port 8888 |
| `OTEL_LOG_LEVEL` | `info` | No | Collector log level |
| `APP_LOG_DIR` | none | Yes (compose only) | Host directory mounted read-only at `/var/log/app` |

## Tunables

| Setting (YAML path) | Value shipped | When to change |
|---|---|---|
| `receivers.file_log.start_at` | `${LOG_START_AT:-end}` | `beginning` for a one-off backfill only |
| `receivers.file_log.exclude` | `*.gz`, `*.zip`, `*.tmp` | Add rotated file patterns your logrotate produces |
| `receivers.file_log.max_log_size` | `1MiB` | Raise if single log entries are larger (they are truncated) |
| `receivers.file_log.include_file_path` | `true` | Set `false` to drop `log.file.path` if not needed |
| `receivers.file_log.operators[parse_plain_severity].regex` | level keyword regex | Anchor it to your log format to avoid matching words like "error" in messages |
| `extensions.file_storage/checkpoints.directory` | `${OTEL_STORAGE_DIR}` | Point at a persistent volume |
| `exporters.otlp_http/loki.sending_queue.queue_size` | `1000` | Raise for longer Loki outages |
| `exporters.otlp_http/loki.retry_on_failure.max_elapsed_time` | `300s` | How long an outage is retried before data is dropped |
| `processors.batch.send_batch_size` | `2048` | Lower if Loki rejects request size |

## Pitfalls

- The contrib `loki` exporter is gone. Use OTLP to Loki 3.x `/otlp`; do not add `/v1/logs` yourself or you get `/otlp/v1/logs/v1/logs`.
- Checkpoints on an ephemeral or unwritable directory mean restarts re-read files (duplicates) or skip to the end (gaps). The directory must persist and be writable by uid 10001.
- `start_at: beginning` on a host with large existing files floods Loki and may hit ingestion rate limits. Use it only for deliberate backfills.
- The plain-text regex matches the FIRST level keyword anywhere in the line; a message like `INFO retrying after error` is parsed as INFO, but `connection error ignored` is ERROR. Tighten the regex to your format.
- Loki promotes only a small set of resource attributes (such as `service.name`) to stream labels; everything else becomes structured metadata. Do not promote high-cardinality attributes to labels.
- Multi-line entries (stack traces) are split into separate records by default; add a `multiline` config for your format if needed.
- Loki rejects logs older than its `reject_old_samples_max_age` and entries out of its accepted time window; old backfills may be refused.
- A literal `$` in the config must be written `$$`.

## Security notes

- Log files are mounted read-only; the collector runs as uid 10001 with read-only rootfs, `cap_drop: [ALL]` and `no-new-privileges`. Only `./data` is writable.
- No ports are published by compose; health_check and telemetry stay on `localhost` by default.
- Use `https://` for `LOKI_OTLP_ENDPOINT` across untrusted networks. `X-Scope-OrgID` is a tenant selector, not authentication.
- Logs often contain PII and secrets; start with [`snippets/pii-redaction-basic`](../../snippets/pii-redaction-basic/) before export (the hardened version is recipe 08 in the full pack).
- Keep credentials in environment variables, never in YAML or committed `.env` files.

## What the automated test proves

These behavioural tests run in the end-to-end suite of the [full pack](https://store.fractaltechware.com/l/otel-collector-recipes?utm_source=github&utm_medium=readme&utm_campaign=free-repo) against this exact config. This free repo's CI runs `otelcol-contrib validate` on every config.

- A file with a JSON line, a plain-text `WARN` line and a line without a level is tailed from the beginning; all 3 records arrive.
- The JSON line gets `severityText=ERROR` and `severityNumber=17`, and its field `order_id` becomes an attribute.
- The plain-text `WARN` line gets `severityNumber=13`.
- `service.name` is inserted from `LOG_SERVICE_NAME` (used by Loki as `service_name`), and every record carries `log.file.path`.
- Every recipe is also run through `otelcol-contrib validate` and started hardened (uid 10001, read-only rootfs, cap-drop ALL, checkpoint dir writable for uid 10001); the test fails on any deprecation warning or error-level line in the logs.

## Troubleshooting

- `permission denied` on the storage directory -> checkpoint volume not owned by uid 10001 -> `sudo chown 10001:10001 data`.
- No logs arrive, no errors -> `start_at: end` and nothing new written, or glob does not match -> append a line to the file, check `LOG_INCLUDE_GLOB` against the in-container path.
- HTTP 404 from Loki -> wrong path or Loki < 3.0 -> use `http://loki:3100/otlp` on Loki 3.x.
- HTTP 401/`no org id` -> multi-tenant Loki without tenant -> set `LOKI_TENANT_ID`.
- Duplicate logs after every restart -> checkpoints not persisted -> mount a persistent volume at `OTEL_STORAGE_DIR`.
