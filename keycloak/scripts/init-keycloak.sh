#!/usr/bin/env bash
set -euo pipefail

KC_LDAP_USERS_MODE="${KC_LDAP_USERS_MODE:-manual}"
LAB_MODE="${LAB_MODE:-manual}"

# LAB_MODE is the master switch: preconfigured forces this component on; manual
# defers to the per-component KC_LDAP_USERS_MODE knob.
if [ "${LAB_MODE}" = "preconfigured" ]; then
    KC_LDAP_USERS_MODE="preconfigured"
fi

if [ "${KC_LDAP_USERS_MODE}" != "preconfigured" ]; then
    echo "LAB_MODE=${LAB_MODE}, KC_LDAP_USERS_MODE=${KC_LDAP_USERS_MODE}; skipping LDAP user federation setup"
    exit 0
fi

KCADM=/opt/keycloak/bin/kcadm.sh
CFG_A=/tmp/kcadm-a.config
CFG_B=/tmp/kcadm-b.config

KEYCLOAK_A_REALM="${KEYCLOAK_A_REALM:-rti}"
KEYCLOAK_B_REALM="${KEYCLOAK_B_REALM:-si}"
KEYCLOAK_LDAP_BIND_PASSWORD="${KEYCLOAK_LDAP_BIND_PASSWORD:-keycloak123}"

# Total number of instances of each web app (1 = base app only). Each instance is
# registered as its OWN Keycloak client (RTI: webapp-rti-oauth2-1, -2, ...; SI:
# webapp-si-saml-1, -2, ...) so SSO is demonstrated across DIFFERENT applications
# in the same realm via delegated auth, not across copies of one client. Instances
# run on incrementing host ports (RTI: 3000, 3001, ...; SI: 4000, 4001, ...) and
# each client's own redirect / ACS URL is registered below.
WEBAPP_RTI_COPIES="${WEBAPP_RTI_COPIES:-1}"
WEBAPP_SI_COPIES="${WEBAPP_SI_COPIES:-1}"

# Audience stamped into Web App A access tokens so the OAuth 2.0 API can verify it.
API_AUDIENCE="${API_AUDIENCE:-oauth2-api}"

# SSO session timeouts (seconds). Short by default so the SSO countdown in
# Web Application B is demonstrable; raise for a more realistic setup.
SSO_SESSION_IDLE_TIMEOUT="${SSO_SESSION_IDLE_TIMEOUT:-300}"
SSO_SESSION_MAX_LIFESPAN="${SSO_SESSION_MAX_LIFESPAN:-300}"

# Join the given arguments into a JSON array of quoted strings.
build_json_array() {
    local out="" item
    for item in "$@"; do
        out+=",\"${item}\""
    done
    echo "[${out#,}]"
}

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

get_client_uuid() {
    local cfg="$1"
    local realm="$2"
    local client_id="$3"
    kc "${cfg}" get clients -r "${realm}" -q clientId="${client_id}" --fields id --format csv --noquotes 2>/dev/null | tr -d '\r' | head -n1
}

# True when a protocol mapper named $4 already exists on client UUID $3.
client_mapper_exists() {
    local cfg="$1" realm="$2" client_uuid="$3" name="$4"
    kc "${cfg}" get "clients/${client_uuid}/protocol-mappers/models" -r "${realm}" 2>/dev/null \
        | grep -Eq "\"name\"[[:space:]]*:[[:space:]]*\"${name}\""
}

ensure_saml_client_property_mapper() {
    local cfg="$1"
    local realm="$2"
    local client_uuid="$3"
    local name="$4"
    local user_property="$5"
    local saml_attr="$6"

    if client_mapper_exists "${cfg}" "${realm}" "${client_uuid}" "${name}"; then
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

ensure_realm() {
    local cfg="$1"
    local realm="$2"

    if kc "${cfg}" get "realms/${realm}" >/dev/null 2>&1; then
        echo "Realm ${realm} already exists"
    else
        kc "${cfg}" create realms -s realm="${realm}" -s enabled=true >/dev/null
        echo "Realm ${realm} created"
    fi
}

ensure_session_timeouts() {
    local cfg="$1"
    local realm="$2"

    kc "${cfg}" update "realms/${realm}" \
        -s ssoSessionIdleTimeout="${SSO_SESSION_IDLE_TIMEOUT}" \
        -s ssoSessionMaxLifespan="${SSO_SESSION_MAX_LIFESPAN}" >/dev/null
    echo "Realm ${realm} SSO session set to idle=${SSO_SESSION_IDLE_TIMEOUT}s max=${SSO_SESSION_MAX_LIFESPAN}s"
}

ensure_ldap_provider() {
    local cfg="$1"
    local realm="$2"
    local provider_name="$3"
    local connection_url="$4"
    local users_dn="$5"
    local bind_dn="$6"

    local realm_id
    realm_id=$(kc "${cfg}" get "realms/${realm}" --fields id --format csv --noquotes 2>/dev/null | tr -d '\r')
    if [ -z "${realm_id}" ]; then
        echo "Cannot resolve realm id for ${realm}" >&2
        return 1
    fi

    if kc "${cfg}" get components -r "${realm}" -q parent="${realm_id}" -q name="${provider_name}" | grep -Eq "\"name\"[[:space:]]*:[[:space:]]*\"${provider_name}\""; then
        echo "LDAP provider ${provider_name} already exists in realm ${realm}"
        return 0
    fi

    # remove any stale providers created with an incorrect parentId so the console lists the new one
    local stale_id
    while IFS= read -r stale_id; do
        [ -n "${stale_id}" ] && kc "${cfg}" delete "components/${stale_id}" -r "${realm}" >/dev/null 2>&1 || true
    done < <(kc "${cfg}" get components -r "${realm}" -q name="${provider_name}" --fields id --format csv --noquotes 2>/dev/null | tr -d '\r')

    kc "${cfg}" create components -r "${realm}" \
        -s name="${provider_name}" \
        -s providerId=ldap \
        -s providerType=org.keycloak.storage.UserStorageProvider \
        -s parentId="${realm_id}" \
        -s 'config.enabled=["true"]' \
        -s 'config.priority=["0"]' \
        -s 'config.editMode=["WRITABLE"]' \
        -s 'config.importEnabled=["true"]' \
        -s 'config.syncRegistrations=["true"]' \
        -s 'config.vendor=["other"]' \
        -s 'config.usernameLDAPAttribute=["uid"]' \
        -s 'config.rdnLDAPAttribute=["uid"]' \
        -s 'config.uuidLDAPAttribute=["entryUUID"]' \
        -s 'config.userObjectClasses=["inetOrgPerson,organizationalPerson,person,top"]' \
        -s 'config.connectionUrl=["'"${connection_url}"'"]' \
        -s 'config.usersDn=["'"${users_dn}"'"]' \
        -s 'config.authType=["simple"]' \
        -s 'config.bindDn=["'"${bind_dn}"'"]' \
        -s 'config.bindCredential=["'"${KEYCLOAK_LDAP_BIND_PASSWORD}"'"]' \
        -s 'config.searchScope=["1"]' \
        -s 'config.pagination=["true"]' >/dev/null

    echo "LDAP provider ${provider_name} created in realm ${realm}"
}

ensure_group_mapper() {
    local cfg="$1"
    local realm="$2"
    local provider_name="$3"
    local groups_dn="$4"

    local provider_id
    provider_id=$(kc "${cfg}" get components -r "${realm}" -q name="${provider_name}" --fields id --format csv --noquotes 2>/dev/null | tr -d '\r')

    if [ -z "${provider_id}" ]; then
        echo "Cannot find LDAP provider ${provider_name} in realm ${realm}" >&2
        return 1
    fi

    if kc "${cfg}" get components -r "${realm}" -q parent="${provider_id}" -q name=group-mapper | grep -q '"name"'; then
        echo "Group mapper already exists in realm ${realm}"
    else
        kc "${cfg}" create components -r "${realm}" \
            -s name=group-mapper \
            -s providerId=group-ldap-mapper \
            -s providerType=org.keycloak.storage.ldap.mappers.LDAPStorageMapper \
            -s parentId="${provider_id}" \
            -s 'config."groups.dn"=["'"${groups_dn}"'"]' \
            -s 'config."group.name.ldap.attribute"=["cn"]' \
            -s 'config."group.object.classes"=["groupOfNames"]' \
            -s 'config."preserve.group.inheritance"=["false"]' \
            -s 'config."membership.ldap.attribute"=["member"]' \
            -s 'config."membership.attribute.type"=["DN"]' \
            -s 'config."membership.user.ldap.attribute"=["uid"]' \
            -s 'config."mode"=["LDAP_ONLY"]' \
            -s 'config."user.roles.retrieve.strategy"=["LOAD_GROUPS_BY_MEMBER_ATTRIBUTE"]' \
            -s 'config."drop.non.existing.groups.during.sync"=["false"]' >/dev/null
        echo "Group mapper created in realm ${realm}"
    fi

    kc "${cfg}" create "user-storage/${provider_id}/sync?action=triggerFullSync" -r "${realm}" >/dev/null 2>&1 || true
}

ensure_oidc_client() {
    local cfg="$1"
    local realm="$2"
    local client_id="$3"
    local redirect_uris="$4"
    local web_origins="$5"

    local uuid
    uuid=$(get_client_uuid "${cfg}" "${realm}" "${client_id}")
    if [ -z "${uuid}" ]; then
        kc "${cfg}" create clients -r "${realm}" \
            -s clientId="${client_id}" \
            -s enabled=true \
            -s protocol=openid-connect \
            -s publicClient=true \
            -s standardFlowEnabled=true \
            -s directAccessGrantsEnabled=false \
            -s 'redirectUris='"${redirect_uris}" \
            -s 'webOrigins='"${web_origins}" \
            -s 'attributes."pkce.code.challenge.method"=S256' \
            -s 'attributes."post.logout.redirect.uris"=+' >/dev/null
        echo "OIDC client ${client_id} created in realm ${realm}"
    else
        # Sync redirect URIs / web origins so newly requested copies are accepted.
        kc "${cfg}" update "clients/${uuid}" -r "${realm}" \
            -s 'redirectUris='"${redirect_uris}" \
            -s 'webOrigins='"${web_origins}" \
            -s 'attributes."pkce.code.challenge.method"=S256' \
            -s 'attributes."post.logout.redirect.uris"=+' >/dev/null
        echo "OIDC client ${client_id} updated in realm ${realm} (redirect URIs synced)"
    fi
}

ensure_oidc_audience_mapper() {
    local cfg="$1"
    local realm="$2"
    local client_uuid="$3"
    local name="$4"
    local audience="$5"

    if client_mapper_exists "${cfg}" "${realm}" "${client_uuid}" "${name}"; then
        echo "Audience mapper ${name} already exists in realm ${realm}"
        return 0
    fi

    kc "${cfg}" create "clients/${client_uuid}/protocol-mappers/models" -r "${realm}" \
        -s name="${name}" \
        -s protocol=openid-connect \
        -s protocolMapper=oidc-audience-mapper \
        -s 'config."included.custom.audience"='"${audience}" \
        -s 'config."access.token.claim"=true' \
        -s 'config."id.token.claim"=false' >/dev/null

    echo "Audience mapper ${name} created in realm ${realm}"
}

ensure_group_membership_mapper() {
    local cfg="$1"
    local realm="$2"
    local client_uuid="$3"
    local name="$4"
    local claim="$5"

    if client_mapper_exists "${cfg}" "${realm}" "${client_uuid}" "${name}"; then
        echo "Group membership mapper ${name} already exists in realm ${realm}"
        return 0
    fi

    kc "${cfg}" create "clients/${client_uuid}/protocol-mappers/models" -r "${realm}" \
        -s name="${name}" \
        -s protocol=openid-connect \
        -s protocolMapper=oidc-group-membership-mapper \
        -s 'config."claim.name"='"${claim}" \
        -s 'config."full.path"=true' \
        -s 'config."access.token.claim"=true' \
        -s 'config."id.token.claim"=false' \
        -s 'config."userinfo.token.claim"=false' >/dev/null

    echo "Group membership mapper ${name} created in realm ${realm}"
}

ensure_saml_client() {
    local cfg="$1"
    local realm="$2"
    local client_id="$3"
    local redirect_uris="$4"
    local acs_url="$5"
    local sls_url="$6"

    local client_uuid
    client_uuid=$(get_client_uuid "${cfg}" "${realm}" "${client_id}")
    if [ -z "${client_uuid}" ]; then
        kc "${cfg}" create clients -r "${realm}" \
            -s clientId="${client_id}" \
            -s name="Web Application B (SAML SP)" \
            -s enabled=true \
            -s protocol=saml \
            -s frontchannelLogout=true \
            -s 'redirectUris='"${redirect_uris}" \
            -s 'attributes."saml.authnstatement"=true' \
            -s 'attributes."saml.server.signature"=true' \
            -s 'attributes."saml.assertion.signature"=true' \
            -s 'attributes."saml.client.signature"=false' \
            -s 'attributes."saml.encrypt"=false' \
            -s 'attributes."saml.force.post.binding"=true' \
            -s 'attributes."saml.signature.algorithm"=RSA_SHA256' \
            -s 'attributes."saml_name_id_format"=username' \
            -s 'attributes."saml_force_name_id_format"=true' \
            -s 'attributes."saml_assertion_consumer_url_post"='"${acs_url}" \
            -s 'attributes."saml_single_logout_service_url_post"='"${sls_url}" \
            -s 'attributes."saml_single_logout_service_url_redirect"='"${sls_url}" >/dev/null
        echo "SAML client ${client_id} created in realm ${realm}"
        client_uuid=$(get_client_uuid "${cfg}" "${realm}" "${client_id}")
    else
        # Sync valid redirect URIs so each copy's ACS/SLS endpoint is accepted.
        kc "${cfg}" update "clients/${client_uuid}" -r "${realm}" \
            -s 'redirectUris='"${redirect_uris}" >/dev/null
        echo "SAML client ${client_id} updated in realm ${realm} (ACS URLs synced)"
    fi

    if [ -n "${client_uuid}" ]; then
        ensure_saml_client_property_mapper "${cfg}" "${realm}" "${client_uuid}" "email"     "email"     "email"
        ensure_saml_client_property_mapper "${cfg}" "${realm}" "${client_uuid}" "firstName" "firstName" "firstName"
        ensure_saml_client_property_mapper "${cfg}" "${realm}" "${client_uuid}" "lastName"  "lastName"  "lastName"
    else
        echo "Could not resolve SAML client UUID for ${client_id}; skipping attribute mappers" >&2
    fi
}

echo "Waiting for Keycloak A and Keycloak B to become reachable"
wait_for_admin_login "${KEYCLOAK_A_URL}" "${CFG_A}"
wait_for_admin_login "${KEYCLOAK_B_URL}" "${CFG_B}"

ensure_realm "${CFG_A}" "${KEYCLOAK_A_REALM}"
ensure_realm "${CFG_B}" "${KEYCLOAK_B_REALM}"

ensure_session_timeouts "${CFG_A}" "${KEYCLOAK_A_REALM}"
ensure_session_timeouts "${CFG_B}" "${KEYCLOAK_B_REALM}"

ensure_ldap_provider \
    "${CFG_A}" \
    "${KEYCLOAK_A_REALM}" \
    "ldap-rti" \
    "ldap://ldap-rti:389" \
    "ou=users,dc=rti,dc=etf,dc=bg,dc=ac,dc=rs" \
    "uid=keycloak,ou=users,dc=rti,dc=etf,dc=bg,dc=ac,dc=rs"

ensure_ldap_provider \
    "${CFG_B}" \
    "${KEYCLOAK_B_REALM}" \
    "ldap-si" \
    "ldap://ldap-si:389" \
    "ou=users,dc=si,dc=etf,dc=bg,dc=ac,dc=rs" \
    "uid=keycloak,ou=users,dc=si,dc=etf,dc=bg,dc=ac,dc=rs"

ensure_group_mapper \
    "${CFG_A}" \
    "${KEYCLOAK_A_REALM}" \
    "ldap-rti" \
    "ou=groups,dc=rti,dc=etf,dc=bg,dc=ac,dc=rs"

ensure_group_mapper \
    "${CFG_B}" \
    "${KEYCLOAK_B_REALM}" \
    "ldap-si" \
    "ou=groups,dc=si,dc=etf,dc=bg,dc=ac,dc=rs"

# Register one distinct OIDC client per RTI instance. Each app gets its own
# client_id, redirect URI, web origin, and token mappers (API audience + groups
# claim) so SSO is exercised across different apps sharing one Keycloak session.
for j in $(seq 1 "${WEBAPP_RTI_COPIES}"); do
    rti_port=$((3000 + j - 1))
    rti_client_id="webapp-rti-oauth2-${j}"
    rti_redirect_uri="http://rti${j}.localhost:${rti_port}/*"
    rti_web_origin="http://rti${j}.localhost:${rti_port}"

    ensure_oidc_client "${CFG_A}" "${KEYCLOAK_A_REALM}" "${rti_client_id}" \
        "$(build_json_array "${rti_redirect_uri}")" \
        "$(build_json_array "${rti_web_origin}")"

    rti_uuid=$(get_client_uuid "${CFG_A}" "${KEYCLOAK_A_REALM}" "${rti_client_id}")
    if [ -n "${rti_uuid}" ]; then
        ensure_oidc_audience_mapper "${CFG_A}" "${KEYCLOAK_A_REALM}" "${rti_uuid}" "oauth2-api-audience" "${API_AUDIENCE}"
        ensure_group_membership_mapper "${CFG_A}" "${KEYCLOAK_A_REALM}" "${rti_uuid}" "groups" "groups"
    else
        echo "Could not resolve OIDC client UUID for ${rti_client_id}; skipping API token mappers" >&2
    fi
done

# Register one distinct SAML SP client per SI instance, each with its own
# entityID/issuer and ACS/SLS endpoints (attribute mappers added per client).
for j in $(seq 1 "${WEBAPP_SI_COPIES}"); do
    si_port=$((4000 + j - 1))
    si_client_id="webapp-si-saml-${j}"
    si_acs_url="http://si${j}.localhost:${si_port}/saml/acs"
    si_sls_url="http://si${j}.localhost:${si_port}/saml/sls"

    ensure_saml_client "${CFG_B}" "${KEYCLOAK_B_REALM}" "${si_client_id}" \
        "$(build_json_array "${si_acs_url}" "${si_sls_url}")" \
        "${si_acs_url}" "${si_sls_url}"
done

echo "LDAP user federation preconfigured"
