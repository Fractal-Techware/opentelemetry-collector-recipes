# Contributing

Thanks for helping improve these OpenTelemetry Collector recipes.

## Reporting issues

Open an issue with the recipe name, your collector version (`otelcol-contrib --version`), the
relevant config snippet (remove secrets) and the collector log lines around the problem.

## Pull requests

1. Keep configs pinned to `otel/opentelemetry-collector-contrib:0.161.0` unless the PR is a version bump.
2. Use current snake_case component names; a change must not introduce deprecation warnings.
3. No secrets or real endpoints in YAML. Use `${env:VAR}` references and document new variables in the recipe README and `.env.example`.
4. Keep the safe defaults: receivers on `localhost`, `tls.insecure: false`, debug output only via overlays.
5. Run `./scripts/validate.sh` (needs Docker) before opening the PR. CI runs the same check.

By contributing you agree that your contribution is licensed under the MIT License.
