#!/usr/bin/env bash
#
# Generate docker-compose.override.yml with extra copies of the web apps to
# demonstrate Single Sign-On (SSO).
#
# The copy counts are the TOTAL number of instances of each app (1 = base app
# only, no extra copies). Extra copies run on incrementing host ports and share a
# single Keycloak login, so signing in to one and opening another logs you in
# automatically.
#
#   RTI (OIDC SPA):   base http://rti1.localhost:3000, copies rti2:3001, rti3:3002, ...
#   SI  (SAML app):   base http://si1.localhost:4000, copies si2:4001, si3:4002, ...
#
# Counts are resolved in this order: environment variable, then .env, then 1.
# Optional positional args override both:  generate-webapp-copies.sh [RTI] [SI].
#
# Docker Compose auto-loads docker-compose.override.yml, so after regenerating
# just run the usual `docker compose up -d --build` (or use ./lab-up.sh, which
# generates and brings the stack up in one step). The extra redirect / ACS URLs
# are registered by keycloak-init, which reads the same counts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
OVERRIDE_FILE="${SCRIPT_DIR}/docker-compose.override.yml"

read_env_int() {
    local name="$1" fallback="$2" value=""
    if [ -n "${!name:-}" ]; then
        value="${!name}"
    elif [ -f "${ENV_FILE}" ]; then
        value="$(grep -E "^[[:space:]]*${name}[[:space:]]*=" "${ENV_FILE}" | tail -n1 | cut -d= -f2- | tr -d '[:space:]')"
    fi
    if [[ "${value}" =~ ^[0-9]+$ ]]; then echo "${value}"; else echo "${fallback}"; fi
}

RTI_COPIES="${1:-$(read_env_int WEBAPP_RTI_COPIES 1)}"
SI_COPIES="${2:-$(read_env_int WEBAPP_SI_COPIES 1)}"
[[ "${RTI_COPIES}" =~ ^[0-9]+$ ]] && [ "${RTI_COPIES}" -ge 1 ] || RTI_COPIES=1
[[ "${SI_COPIES}"  =~ ^[0-9]+$ ]] && [ "${SI_COPIES}"  -ge 1 ] || SI_COPIES=1

body=""
emitted=0
append() { body+="$1"$'\n'; }

for ((j = 2; j <= RTI_COPIES; j++)); do
    emitted=1
    port=$((3000 + j - 1))
    append "  webapp-rti-oauth2-${j}:"
    append "    build:"
    append "      context: ./webapp-rti-oauth2"
    append "      dockerfile: Dockerfile"
    append "    environment:"
    append "      VITE_OIDC_AUTHORITY: \${WEBAPP_A_OIDC_AUTHORITY:-http://rti.localhost:8081/realms/rti}"
    append "      VITE_OIDC_CLIENT_ID: webapp-rti-oauth2-${j}"
    append "      VITE_OIDC_REDIRECT_URI: http://rti${j}.localhost:${port}"
    append "      VITE_API_BASE_URL: \${WEBAPP_A_API_BASE_URL:-http://localhost:5000}"
    append "      VITE_APP_INSTANCE: \"${j}\""
    append "    ports:"
    append "      - \"${port}:3000\""
    append "    networks:"
    append "      - lab-network"
    append "    depends_on:"
    append "      keycloak-rti:"
    append "        condition: service_healthy"
    append "      keycloak-init:"
    append "        condition: service_completed_successfully"
    append "      keycloak-federation-init:"
    append "        condition: service_completed_successfully"
done

for ((j = 2; j <= SI_COPIES; j++)); do
    emitted=1
    port=$((4000 + j - 1))
    append "  webapp-si-saml-backend-${j}:"
    append "    build:"
    append "      context: ./webapp-si-saml/backend"
    append "      dockerfile: Dockerfile"
    append "    environment:"
    append "      PORT: \"4001\""
    append "      FRONTEND_URL: http://si${j}.localhost:${port}"
    append "      SAML_ENTRY_POINT: \${WEBAPP_B_SAML_ENTRY_POINT:-http://si.localhost:8082/realms/si/protocol/saml}"
    append "      SAML_IDP_ISSUER: \${WEBAPP_B_SAML_IDP_ISSUER:-http://si.localhost:8082/realms/si}"
    append "      SAML_ISSUER: webapp-si-saml-${j}"
    append "      SAML_ACS_URL: http://si${j}.localhost:${port}/saml/acs"
    append "      SAML_METADATA_URL: \${WEBAPP_B_SAML_METADATA_URL:-http://keycloak-si:8080/realms/si/protocol/saml/descriptor}"
    append "      SESSION_SECRET: \${WEBAPP_B_SESSION_SECRET:-webapp-si-saml-dev-secret}"
    append "    networks:"
    append "      - lab-network"
    append "    extra_hosts:"
    append "      - \"rti.localhost:host-gateway\""
    append "      - \"si.localhost:host-gateway\""
    append "    depends_on:"
    append "      keycloak-si:"
    append "        condition: service_healthy"
    append "      keycloak-init:"
    append "        condition: service_completed_successfully"
    append "      keycloak-federation-init:"
    append "        condition: service_completed_successfully"
    append "  webapp-si-saml-frontend-${j}:"
    append "    build:"
    append "      context: ./webapp-si-saml/frontend"
    append "      dockerfile: Dockerfile"
    append "    environment:"
    append "      BACKEND_URL: http://webapp-si-saml-backend-${j}:4001"
    append "      VITE_APP_INSTANCE: \"${j}\""
    append "    ports:"
    append "      - \"${port}:4000\""
    append "    networks:"
    append "      - lab-network"
    append "    depends_on:"
    append "      webapp-si-saml-backend-${j}:"
    append "        condition: service_started"
done

{
    echo "# AUTO-GENERATED by generate-webapp-copies.(sh|ps1) - do not edit by hand."
    echo "# Extra web app copies for the SSO demo (RTI copies=${RTI_COPIES}, SI copies=${SI_COPIES})."
    echo "# Regenerate after changing WEBAPP_RTI_COPIES / WEBAPP_SI_COPIES."
    if [ "${emitted}" -eq 1 ]; then
        echo "services:"
        printf '%s' "${body}"
    else
        echo "services: {}"
    fi
} > "${OVERRIDE_FILE}"

echo "Wrote ${OVERRIDE_FILE} (RTI instances=${RTI_COPIES}, SI instances=${SI_COPIES})."
if [ "${emitted}" -eq 1 ]; then
    [ "${RTI_COPIES}" -gt 1 ] && echo "RTI copies on ports: $(seq -s ', ' 3001 $((3000 + RTI_COPIES - 1)))"
    [ "${SI_COPIES}"  -gt 1 ] && echo "SI  copies on ports: $(seq -s ', ' 4001 $((4000 + SI_COPIES - 1)))"
else
    echo "No extra copies requested (both counts are 1)."
fi
