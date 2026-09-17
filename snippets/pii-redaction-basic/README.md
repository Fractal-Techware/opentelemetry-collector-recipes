# Basic PII redaction for the OpenTelemetry Collector (OTTL snippet)

> **Basic version.** This is a small, readable starting point for masking personal data and
> credentials with the `transform` processor. It is not a compliance control. The hardened,
> end-to-end-tested version is recipe **08 - PII & secret redaction** in the
> [full pack (Pro and Studio)](https://fractaltechware.gumroad.com/l/otel-collector-recipes?utm_source=github&utm_medium=readme&utm_campaign=free-repo).

Masks emails and payment-card-like numbers and deletes credential headers in **traces and logs**
before anything leaves the collector.

## What it does

| Data | Where | Result |
|---|---|---|
| Email addresses | log body (string), log attributes, span attributes, span name | `[REDACTED_EMAIL]` |
| 13-16 digit card-like numbers (spaces/dashes allowed) | log body (string), log and span attributes | `[REDACTED_CARD]` |
| `authorization`, `cookie`, `set-cookie`, `x-api-key` (also as `http.request.header.*`, any case) | log and span attributes | attribute deleted |

Example (actual collector debug output after sending a log and a span through this config):

```
Body: Str(payment by [REDACTED_EMAIL] card [REDACTED_CARD] ok)
     -> user.email: Str([REDACTED_EMAIL])
     -> order.status: Str(paid)
    Name           : lookup user [REDACTED_EMAIL]
     -> card: Str([REDACTED_CARD])
     -> http.route: Str(/users/:id)
```

The `http.request.header.authorization`, `Cookie` and `x-api-key` attributes that were sent are gone.

## Pipeline

```
otlp -> memory_limiter -> transform/pii_basic -> batch -> otlp_grpc
```

Redaction sits before `batch` and before every exporter, so unredacted data never leaves the process.
If you add a `debug` exporter, keep it after this processor too.

## Quickstart

```bash
cp .env.example .env      # set OTLP_EXPORT_ENDPOINT
docker compose up -d
docker compose logs -f otelcol
```

Or drop the `transform/pii_basic` block into your own config and add it to your `traces` and
`logs` pipelines right after `memory_limiter`.

Validate:

```bash
docker run --rm -v "$PWD:/cfg:ro" -e OTLP_EXPORT_ENDPOINT=gateway:4317 \
  otel/opentelemetry-collector-contrib:0.161.0 validate --config=/cfg/config.yaml
```

## Known gaps in the basic version

- **Integer attributes are not scanned.** A card number sent as an `int` attribute passes through.
- No IPv4/IPv6 masking, no secrets in URL query strings (`?token=...`), no `Bearer`/`Basic` tokens inside free text.
- Span events, span links and resource attributes are not scanned.
- No key-name catch-all (`*password*`, `*secret*`, `*token*`).
- Structured (map) log bodies are left alone; only string bodies are rewritten.
- False positives: any 13-16 digit run is masked, including long order or account IDs.
- Metrics are not covered (they rarely carry PII, but label values can).

Recipe 08 in the full pack closes these gaps with a two-layer design (OTTL + `redaction`
processor), a tighter card pattern that keeps typical order IDs, and an automated test that sends
real payloads and asserts exactly what arrives.

## Pitfalls

- The collector treats `$` as an environment variable reference. In regexes write `$$` for a literal `$` (this file does, in the header-deletion pattern).
- `error_mode: ignore` keeps data flowing if a statement fails on unexpected data; use `propagate` while developing to see errors.
- Order matters: a processor placed before `transform/pii_basic` (for example one that copies attributes to span names) can move PII somewhere this snippet does not look.
- Redaction in the collector does not remove data your SDKs already wrote to local logs or sent to other destinations.
