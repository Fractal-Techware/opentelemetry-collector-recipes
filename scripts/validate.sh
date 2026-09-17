#!/usr/bin/env bash
# Validate every collector config in this repo with the pinned otelcol-contrib image.
# Usage: ./scripts/validate.sh
set -euo pipefail

IMAGE="${OTELCOL_IMAGE:-otel/opentelemetry-collector-contrib:0.161.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Placeholder values so required ${env:...} references resolve.
ENV_ARGS=(-e OTLP_EXPORT_ENDPOINT=gateway.example.internal:4317)

run_validate() {
  echo "==> validate $*"
  local args=()
  for f in "$@"; do args+=("--config=/cfg/$f"); done
  docker run --rm -v "$ROOT:/cfg:ro" "${ENV_ARGS[@]}" "$IMAGE" validate "${args[@]}"
}

fail=0
while IFS= read -r cfg; do
  run_validate "$cfg" || fail=1
done < <(find recipes snippets -name config.yaml | sort)

# Overlays are validated merged with their base config.
while IFS= read -r overlay; do
  run_validate "$(dirname "$overlay")/config.yaml" "$overlay" || fail=1
done < <(find recipes snippets -name '*.overlay.yaml' | sort)

if [ "$fail" -ne 0 ]; then
  echo "FAILED" >&2
  exit 1
fi
echo "All configs valid."
