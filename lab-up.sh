#!/usr/bin/env bash
#
# Bring the lab up. First regenerates docker-compose.override.yml from the copy
# counts (WEBAPP_RTI_COPIES / WEBAPP_SI_COPIES), then runs `docker compose up`.
# When either count is > 1 the extra web app copies are generated and started;
# when both are 1 the override is empty and only the base apps come up.
#
# Usage:
#   ./lab-up.sh                 # counts from .env
#   ./lab-up.sh 3 2             # override RTI=3, SI=2 for this run and .env resolution
#   ./lab-up.sh 3 2 -- <args>   # pass extra args to `docker compose up`
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

# Optional positional counts: lab-up.sh [RTI_COPIES] [SI_COPIES] [-- <compose args>]
if [[ "${1:-}" =~ ^[0-9]+$ ]]; then export WEBAPP_RTI_COPIES="$1"; shift; fi
if [[ "${1:-}" =~ ^[0-9]+$ ]]; then export WEBAPP_SI_COPIES="$1"; shift; fi
[ "${1:-}" = "--" ] && shift || true

./generate-webapp-copies.sh

echo "Starting stack: docker compose up -d --build ${*}"
docker compose up -d --build "$@"
