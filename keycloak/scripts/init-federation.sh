#!/usr/bin/env bash
set -euo pipefail

KC_FEDERATION_MODE="${KC_FEDERATION_MODE:-manual}"
LAB_MODE="${LAB_MODE:-manual}"

# LAB_MODE is the master switch: preconfigured forces this component on; manual
# defers to the per-component KC_FEDERATION_MODE knob.
if [ "${LAB_MODE}" = "preconfigured" ]; then
    KC_FEDERATION_MODE="preconfigured"
fi

if [ "${KC_FEDERATION_MODE}" != "preconfigured" ]; then
    echo "LAB_MODE=${LAB_MODE}, KC_FEDERATION_MODE=${KC_FEDERATION_MODE}; skipping Keycloak federation setup"
    exit 0
fi

KCADM=/opt/keycloak/bin/kcadm.sh
CFG_A=/tmp/kcadm-fed-a.config
CFG_B=/tmp/kcadm-fed-b.config

KEYCLOAK_A_REALM="${KEYCLOAK_A_REALM:-rti}"
KEYCLOAK_B_REALM="${KEYCLOAK_B_REALM:-si}"

# Browser/back-channel reachable hostnames (rti.localhost / si.localhost resolve
# inside the containers via the compose extra_hosts mappings).
KEYCLOAK_A_HOSTNAME="${KEYCLOAK_A_HOSTNAME:-http://rti.localhost:8081}"
KEYCLOAK_B_HOSTNAME="${KEYCLOAK_B_HOSTNAME:-http://si.localhost:8082}"

# Shared secret for the OIDC broker client (lab-only value).
BROKER_SI_CLIENT_ID="broker-si"
BROKER_SI_SECRET="${BROKER_SI_SECRET:-broker-si-secret}"

# Federation aliases (must match the /broker/<alias>/endpoint URLs).
OIDC_IDP_ALIAS="oidc-rti"
SAML_IDP_ALIAS="saml-si"

# Group whose membership grants API access; propagated across SAML federation
# so brokered SI users who hold it can invoke the OAuth 2.0 API from RTI.
API_REQUIRED_GROUP="${API_REQUIRED_GROUP:-api-access}"

# Whether a brokered logout in one realm cascades to the other (cross-realm SLO).
# off (default) isolates logout to the initiating realm to avoid the
# bidirectional-brokering logout loop; on restores cross-realm single logout.
KC_FEDERATION_LOGOUT_PROPAGATION="${KC_FEDERATION_LOGOUT_PROPAGATION:-off}"

wait_for_admin_login() {
    local server="$1"
    local config_file="$2"

    for attempt in $(seq 1 90); do
        if "${KCADM}" config credentials \
            --server "${server}" \
            --realm master \
            --user "${KEYCLOAK_ADMIN_USER}" \
            --password "${KEYCLOAK_ADMIN_PASSWORD}" \
            --config "${config_file}" >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done

    echo "Could not authenticate to ${server} as admin" >&2
    return 1
}

kc() {
    local cfg="$1"
    shift
    "${KCADM}" "$@" --config "${cfg}"
}

# ---------------------------------------------------------------------------
# OIDC direction: RTI users log in to SI (SI trusts RTI).
#   - Keycloak A (rti): confidential client "broker-si" that SI uses.
#   - Keycloak B (si):  OIDC identity provider "oidc-rti" pointing back at A.
# ---------------------------------------------------------------------------

ensure_oidc_broker_client() {
    local cfg="$1"
    local realm="$2"
    local client_id="$3"
    local secret="$4"
    local redirect_uri="$5"

    if kc "${cfg}" get clients -r "${realm}" -q clientId="${client_id}" | grep -Eq "\"clientId\"[[:space:]]*:[[:space:]]*\"${client_id}\""; then
        echo "OIDC broker client ${client_id} already exists in realm ${realm}"
        return 0
    fi

    kc "${cfg}" create clients -r "${realm}" \
        -s clientId="${client_id}" \
        -s enabled=true \
        -s protocol=openid-connect \
        -s publicClient=false \
        -s secret="${secret}" \
        -s standardFlowEnabled=true \
        -s directAccessGrantsEnabled=false \
        -s 'redirectUris=["'"${redirect_uri}"'"]' >/dev/null

    echo "OIDC broker client ${client_id} created in realm ${realm}"
}

ensure_oidc_identity_provider() {
    local cfg="$1"
    local realm="$2"
    local alias="$3"
    local remote_host="$4"
    local remote_realm="$5"
    local client_id="$6"
    local secret="$7"

    if kc "${cfg}" get "identity-provider/instances/${alias}" -r "${realm}" >/dev/null 2>&1; then
        echo "OIDC identity provider ${alias} already exists in realm ${realm}"
        return 0
    fi

    local base="${remote_host}/realms/${remote_realm}"

    # Only forward logout upstream when cross-realm propagation is enabled.
    local logout_url=""
    if [ "${KC_FEDERATION_LOGOUT_PROPAGATION}" = "on" ]; then
        logout_url="${base}/protocol/openid-connect/logout"
    fi

    kc "${cfg}" create identity-provider/instances -r "${realm}" \
        -s alias="${alias}" \
        -s displayName="Login with RTI (OIDC)" \
        -s providerId=oidc \
        -s enabled=true \
        -s trustEmail=true \
        -s storeToken=false \
        -s config.clientId="${client_id}" \
        -s config.clientSecret="${secret}" \
        -s config.clientAuthMethod=client_secret_post \
        -s config.issuer="${base}" \
        -s config.authorizationUrl="${base}/protocol/openid-connect/auth" \
        -s config.tokenUrl="${base}/protocol/openid-connect/token" \
        -s config.userInfoUrl="${base}/protocol/openid-connect/userinfo" \
        -s config.logoutUrl="${logout_url}" \
        -s config.jwksUrl="${base}/protocol/openid-connect/certs" \
        -s config.useJwksUrl=true \
        -s config.validateSignature=true \
        -s config.defaultScope="openid profile email" \
        -s config.syncMode=IMPORT >/dev/null

    echo "OIDC identity provider ${alias} created in realm ${realm}"
}

# ---------------------------------------------------------------------------
# SAML direction: SI users log in to RTI (RTI trusts SI).
#   - Keycloak A (rti): SAML identity provider "saml-si" pointing at B.
#   - Keycloak B (si):  SAML client (SP) representing RTI's broker endpoint.
# Signature validation is disabled on both sides to keep the lab reset-safe
# (realm keys are regenerated on `docker compose down -v`).
# ---------------------------------------------------------------------------

ensure_saml_identity_provider() {
    local cfg="$1"
    local realm="$2"
    local alias="$3"
    local remote_host="$4"
    local remote_realm="$5"

    if kc "${cfg}" get "identity-provider/instances/${alias}" -r "${realm}" >/dev/null 2>&1; then
        echo "SAML identity provider ${alias} already exists in realm ${realm}"
        return 0
    fi

    local saml_endpoint="${remote_host}/realms/${remote_realm}/protocol/saml"

    # Only forward SAML single logout upstream when cross-realm propagation is enabled.
    local slo_url=""
    local post_logout="false"
    if [ "${KC_FEDERATION_LOGOUT_PROPAGATION}" = "on" ]; then
        slo_url="${saml_endpoint}"
        post_logout="true"
    fi

    kc "${cfg}" create identity-provider/instances -r "${realm}" \
        -s alias="${alias}" \
        -s displayName="Login with SI (SAML)" \
        -s providerId=saml \
        -s enabled=true \
        -s trustEmail=true \
        -s config.singleSignOnServiceUrl="${saml_endpoint}" \
        -s config.singleLogoutServiceUrl="${slo_url}" \
        -s config.nameIDPolicyFormat="urn:oasis:names:tc:SAML:2.0:nameid-format:persistent" \
        -s config.postBindingResponse=true \
        -s config.postBindingAuthnRequest=true \
        -s config.postBindingLogout="${post_logout}" \
        -s config.wantAuthnRequestsSigned=false \
        -s config.wantAssertionsSigned=false \
        -s config.validateSignature=false \
        -s config.signatureAlgorithm=RSA_SHA256 \
        -s config.principalType=SUBJECT \
        -s config.syncMode=IMPORT >/dev/null

    echo "SAML identity provider ${alias} created in realm ${realm}"
}

ensure_saml_sp_client() {
    local cfg="$1"
    local realm="$2"
    local sp_host="$3"
    local sp_realm="$4"
    local alias="$5"

    # The SP entityID is the consuming realm's base URL; its ACS is the broker endpoint.
    local entity_id="${sp_host}/realms/${sp_realm}"
    local acs_url="${entity_id}/broker/${alias}/endpoint"

    if kc "${cfg}" get clients -r "${realm}" -q clientId="${entity_id}" | grep -Eq "\"clientId\""; then
        echo "SAML SP client ${entity_id} already exists in realm ${realm}"
        return 0
    fi

    kc "${cfg}" create clients -r "${realm}" \
        -s clientId="${entity_id}" \
        -s name="RTI broker (SAML SP)" \
        -s enabled=true \
        -s protocol=saml \
        -s 'redirectUris=["'"${acs_url}"'"]' \
        -s 'attributes."saml.authnstatement"=true' \
        -s 'attributes."saml.server.signature"=false' \
        -s 'attributes."saml.assertion.signature"=false' \
        -s 'attributes."saml.client.signature"=false' \
        -s 'attributes."saml.force.post.binding"=true' \
        -s 'attributes."saml_name_id_format"=persistent' \
        -s 'attributes."saml_assertion_consumer_url_post"='"${acs_url}" \
        -s 'attributes."saml_single_logout_service_url_post"='"${acs_url}" >/dev/null

    echo "SAML SP client ${entity_id} created in realm ${realm}"
}

# ---------------------------------------------------------------------------
# Attribute mappers. The generic OIDC broker already imports the standard
# claims (email, given_name, family_name), so OIDC needs no extra mappers.
# SAML carries nothing but the NameID by default, so it needs the SP client to
# EMIT the attributes and the IdP to IMPORT them.
# ---------------------------------------------------------------------------

get_client_uuid() {
    local cfg="$1"
    local realm="$2"
    local client_id="$3"
    kc "${cfg}" get clients -r "${realm}" -q clientId="${client_id}" --fields id --format csv --noquotes 2>/dev/null | tr -d '\r' | head -n1
}

idp_mapper_exists() {
    local cfg="$1"
    local realm="$2"
    local alias="$3"
    local name="$4"
    kc "${cfg}" get "identity-provider/instances/${alias}/mappers" -r "${realm}" 2>/dev/null \
        | grep -Eq "\"name\"[[:space:]]*:[[:space:]]*\"${name}\""
}

ensure_saml_idp_mapper() {
    local cfg="$1"
    local realm="$2"
    local alias="$3"
    local name="$4"
    local saml_attr="$5"
    local user_attr="$6"

    if idp_mapper_exists "${cfg}" "${realm}" "${alias}" "${name}"; then
        echo "SAML IdP mapper ${name} already exists on ${alias} (${realm})"
        return 0
    fi

    kc "${cfg}" create "identity-provider/instances/${alias}/mappers" -r "${realm}" \
        -s name="${name}" \
        -s identityProviderAlias="${alias}" \
        -s identityProviderMapper=saml-user-attribute-idp-mapper \
        -s 'config."syncMode"=INHERIT' \
        -s 'config."attribute.name"='"${saml_attr}" \
        -s 'config."user.attribute"='"${user_attr}" >/dev/null

    echo "SAML IdP mapper ${name} created on ${alias} (${realm})"
}

ensure_saml_client_property_mapper() {
    local cfg="$1"
    local realm="$2"
    local client_uuid="$3"
    local name="$4"
    local user_property="$5"
    local saml_attr="$6"

    if kc "${cfg}" get "clients/${client_uuid}/protocol-mappers/models" -r "${realm}" 2>/dev/null \
        | grep -Eq "\"name\"[[:space:]]*:[[:space:]]*\"${name}\""; then
        echo "SAML client mapper ${name} already exists in realm ${realm}"
        return 0
    fi

    kc "${cfg}" create "clients/${client_uuid}/protocol-mappers/models" -r "${realm}" \
        -s name="${name}" \
        -s protocol=saml \
        -s protocolMapper=saml-user-property-mapper \
        -s 'config."user.attribute"='"${user_property}" \
        -s 'config."attribute.name"='"${saml_attr}" \
        -s 'config."attribute.nameformat"=Basic' \
        -s 'config."friendly.name"='"${name}" >/dev/null

    echo "SAML client mapper ${name} created in realm ${realm}"
}

# SP client on SI emits the user's group memberships as a single SAML attribute
# so RTI can decide whether the brokered user is entitled to the API.
ensure_saml_client_group_mapper() {
    local cfg="$1"
    local realm="$2"
    local client_uuid="$3"
    local name="$4"
    local saml_attr="$5"

    if kc "${cfg}" get "clients/${client_uuid}/protocol-mappers/models" -r "${realm}" 2>/dev/null \
        | grep -Eq "\"name\"[[:space:]]*:[[:space:]]*\"${name}\""; then
        echo "SAML client group mapper ${name} already exists in realm ${realm}"
        return 0
    fi

    kc "${cfg}" create "clients/${client_uuid}/protocol-mappers/models" -r "${realm}" \
        -s name="${name}" \
        -s protocol=saml \
        -s protocolMapper=saml-group-membership-mapper \
        -s 'config."attribute.name"='"${saml_attr}" \
        -s 'config."attribute.nameformat"=Basic' \
        -s 'config."single"=true' \
        -s 'config."full.path"=false' >/dev/null

    echo "SAML client group mapper ${name} created in realm ${realm}"
}

# Create a realm group if it does not exist so the IdP group mapper has a target.
ensure_realm_group() {
    local cfg="$1"
    local realm="$2"
    local group_name="$3"

    if kc "${cfg}" get groups -r "${realm}" -q search="${group_name}" --fields name --format csv --noquotes 2>/dev/null \
        | tr -d '\r' | grep -Fxq "${group_name}"; then
        echo "Realm group ${group_name} already exists in realm ${realm}"
        return 0
    fi

    kc "${cfg}" create groups -r "${realm}" -s name="${group_name}" >/dev/null
    echo "Realm group ${group_name} created in realm ${realm}"
}

# On RTI, place brokered SI users into the target group only when their incoming
# SAML "groups" attribute contains the matching value (FORCE re-evaluates each login).
ensure_saml_group_idp_mapper() {
    local cfg="$1"
    local realm="$2"
    local alias="$3"
    local name="$4"
    local saml_attr="$5"
    local attr_value="$6"
    local group_path="$7"

    if idp_mapper_exists "${cfg}" "${realm}" "${alias}" "${name}"; then
        echo "SAML group IdP mapper ${name} already exists on ${alias} (${realm})"
        return 0
    fi

    kc "${cfg}" create "identity-provider/instances/${alias}/mappers" -r "${realm}" -f - >/dev/null <<JSON
{
  "name": "${name}",
  "identityProviderAlias": "${alias}",
  "identityProviderMapper": "saml-advanced-group-idp-mapper",
  "config": {
    "syncMode": "FORCE",
    "are.attribute.values.regex": "false",
    "attributes": "[{\"key\":\"${saml_attr}\",\"value\":\"${attr_value}\"}]",
    "group": "${group_path}"
  }
}
JSON

    echo "SAML group IdP mapper ${name} created on ${alias} (${realm})"
}

echo "Waiting for Keycloak A and Keycloak B to become reachable"
wait_for_admin_login "${KEYCLOAK_A_URL}" "${CFG_A}"
wait_for_admin_login "${KEYCLOAK_B_URL}" "${CFG_B}"

# OIDC: RTI users -> SI
ensure_oidc_broker_client \
    "${CFG_A}" \
    "${KEYCLOAK_A_REALM}" \
    "${BROKER_SI_CLIENT_ID}" \
    "${BROKER_SI_SECRET}" \
    "${KEYCLOAK_B_HOSTNAME}/realms/${KEYCLOAK_B_REALM}/broker/${OIDC_IDP_ALIAS}/endpoint/*"

ensure_oidc_identity_provider \
    "${CFG_B}" \
    "${KEYCLOAK_B_REALM}" \
    "${OIDC_IDP_ALIAS}" \
    "${KEYCLOAK_A_HOSTNAME}" \
    "${KEYCLOAK_A_REALM}" \
    "${BROKER_SI_CLIENT_ID}" \
    "${BROKER_SI_SECRET}"

# SAML: SI users -> RTI
ensure_saml_identity_provider \
    "${CFG_A}" \
    "${KEYCLOAK_A_REALM}" \
    "${SAML_IDP_ALIAS}" \
    "${KEYCLOAK_B_HOSTNAME}" \
    "${KEYCLOAK_B_REALM}"

ensure_saml_sp_client \
    "${CFG_B}" \
    "${KEYCLOAK_B_REALM}" \
    "${KEYCLOAK_A_HOSTNAME}" \
    "${KEYCLOAK_A_REALM}" \
    "${SAML_IDP_ALIAS}"

# SAML SP client on SI: emit user properties as assertion attributes
SAML_SP_ENTITY_ID="${KEYCLOAK_A_HOSTNAME}/realms/${KEYCLOAK_A_REALM}"
SAML_SP_UUID=$(get_client_uuid "${CFG_B}" "${KEYCLOAK_B_REALM}" "${SAML_SP_ENTITY_ID}")
if [ -n "${SAML_SP_UUID}" ]; then
    ensure_saml_client_property_mapper "${CFG_B}" "${KEYCLOAK_B_REALM}" "${SAML_SP_UUID}" "email"     "email"     "email"
    ensure_saml_client_property_mapper "${CFG_B}" "${KEYCLOAK_B_REALM}" "${SAML_SP_UUID}" "firstName" "firstName" "firstName"
    ensure_saml_client_property_mapper "${CFG_B}" "${KEYCLOAK_B_REALM}" "${SAML_SP_UUID}" "lastName"  "lastName"  "lastName"
    ensure_saml_client_group_mapper "${CFG_B}" "${KEYCLOAK_B_REALM}" "${SAML_SP_UUID}" "groups" "groups"
else
    echo "Could not resolve SAML SP client UUID for ${SAML_SP_ENTITY_ID}; skipping client mappers" >&2
fi

# SAML attribute importers on RTI (saml-si): assertion attributes -> user fields
ensure_saml_idp_mapper "${CFG_A}" "${KEYCLOAK_A_REALM}" "${SAML_IDP_ALIAS}" "email"     "email"     "email"
ensure_saml_idp_mapper "${CFG_A}" "${KEYCLOAK_A_REALM}" "${SAML_IDP_ALIAS}" "firstName" "firstName" "firstName"
ensure_saml_idp_mapper "${CFG_A}" "${KEYCLOAK_A_REALM}" "${SAML_IDP_ALIAS}" "lastName"  "lastName"  "lastName"

# Group propagation on RTI (saml-si): grant the API group to brokered SI users
# whose assertion carries groups=api-access, so they can invoke the OAuth 2.0 API.
ensure_realm_group "${CFG_A}" "${KEYCLOAK_A_REALM}" "${API_REQUIRED_GROUP}"
ensure_saml_group_idp_mapper \
    "${CFG_A}" \
    "${KEYCLOAK_A_REALM}" \
    "${SAML_IDP_ALIAS}" \
    "api-access-group" \
    "groups" \
    "${API_REQUIRED_GROUP}" \
    "/${API_REQUIRED_GROUP}"

echo "Keycloak federation preconfigured"
