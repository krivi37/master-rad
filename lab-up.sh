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

if [ ! -e .env ]; then
	if [ ! -f .env.example ]; then
		echo "Cannot create .env because .env.example is missing." >&2
		exit 1
	fi

	for variable in \
		LDAP_RTI_ADMIN_PASSWORD \
		LDAP_SI_ADMIN_PASSWORD \
		KEYCLOAK_ADMIN_PASSWORD \
		KEYCLOAK_LDAP_BIND_PASSWORD \
		WEBAPP_B_SESSION_SECRET; do
		if ! grep -q "^${variable}=" .env.example; then
			echo "Missing ${variable} in .env.example." >&2
			exit 1
		fi
	done

	env_temp="$(mktemp .env.tmp.XXXXXX)"
	trap 'rm -f "$env_temp"' EXIT
	sed \
		-e 's|^LDAP_RTI_ADMIN_PASSWORD=.*|LDAP_RTI_ADMIN_PASSWORD=admin-ldap|' \
		-e 's|^LDAP_SI_ADMIN_PASSWORD=.*|LDAP_SI_ADMIN_PASSWORD=admin-ldap|' \
		-e 's|^KEYCLOAK_ADMIN_PASSWORD=.*|KEYCLOAK_ADMIN_PASSWORD=admin-keycloak|' \
		-e 's|^KEYCLOAK_LDAP_BIND_PASSWORD=.*|KEYCLOAK_LDAP_BIND_PASSWORD=admin-ldap|' \
		-e 's|^WEBAPP_B_SESSION_SECRET=.*|WEBAPP_B_SESSION_SECRET=webapp-si-saml-session-pass|' \
		.env.example > "$env_temp"
	mv "$env_temp" .env
	trap - EXIT
	echo "Created .env from .env.example with lab development passwords."
fi

if ! command -v docker >/dev/null 2>&1; then
	echo "Docker CLI is not installed or is not available in PATH." >&2
	exit 1
fi

if ! docker info >/dev/null 2>&1; then
	echo "Docker is not running. Starting it..."
	case "$(uname -s)" in
		Darwin)
			open -a Docker
			;;
		Linux)
			sudo systemctl start docker || sudo service docker start
			;;
		*)
			echo "Docker is not running and cannot be started automatically on this platform." >&2
			exit 1
			;;
	esac

	docker_ready=false
	for _ in {1..60}; do
		if docker info >/dev/null 2>&1; then
			docker_ready=true
			break
		fi
		sleep 2
	done

	if [ "$docker_ready" != true ]; then
		echo "Docker did not become ready within 120 seconds." >&2
		exit 1
	fi
fi

# Optional positional counts: lab-up.sh [RTI_COPIES] [SI_COPIES] [-- <compose args>]
if [[ "${1:-}" =~ ^[0-9]+$ ]]; then export WEBAPP_RTI_COPIES="$1"; shift; fi
if [[ "${1:-}" =~ ^[0-9]+$ ]]; then export WEBAPP_SI_COPIES="$1"; shift; fi
[ "${1:-}" = "--" ] && shift || true

./generate-webapp-copies.sh

echo "Starting stack: docker compose up -d --build ${*}"
docker compose up -d --build "$@"
