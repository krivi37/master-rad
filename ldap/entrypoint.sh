#!/usr/bin/env bash
set -euo pipefail

: "${LDAP_BASE_DN:?LDAP_BASE_DN is required}"
: "${LDAP_ADMIN_PASSWORD:?LDAP_ADMIN_PASSWORD is required}"
: "${LDAP_BASE_LDIF:?LDAP_BASE_LDIF is required}"
: "${LDAP_USERS_LDIF:?LDAP_USERS_LDIF is required}"
AUTO_POPULATE="${AUTO_POPULATE:-true}"
LAB_MODE="${LAB_MODE:-manual}"
KEYCLOAK_LDAP_BIND_PASSWORD="${KEYCLOAK_LDAP_BIND_PASSWORD:-keycloak123}"

# LAB_MODE is the master switch: preconfigured forces seeding regardless of the
# per-component AUTO_POPULATE knob; manual defers to AUTO_POPULATE.
if [ "${LAB_MODE,,}" = "preconfigured" ]; then
    AUTO_POPULATE=true
fi

config_dir=/etc/openldap/slapd.d

generate_config() {
    local root_password_hash
    root_password_hash="$(slappasswd -n -s "${LDAP_ADMIN_PASSWORD}")"
    rm -rf "${config_dir:?}"/*
    sed \
        -e "s|@BASE_DN@|${LDAP_BASE_DN}|g" \
        -e "s|@ROOT_PASSWORD_HASH@|${root_password_hash}|g" \
        /etc/openldap/slapd.conf.template > /etc/openldap/slapd.conf
}

generate_config

if [ ! -f /var/lib/ldap/data.mdb ]; then
    echo "Initializing OpenLDAP for ${LDAP_BASE_DN}"
    slapd -f /etc/openldap/slapd.conf -h "ldap://127.0.0.1:389/" -d 0 &
    slapd_pid=$!

    for attempt in $(seq 1 30); do
        if ldapwhoami -x -H ldap://127.0.0.1:389 \
            -D "cn=admin,${LDAP_BASE_DN}" -w "${LDAP_ADMIN_PASSWORD}" >/dev/null 2>&1; then
            break
        fi
        if [ "${attempt}" = "30" ]; then
            echo "OpenLDAP did not become ready" >&2
            exit 1
        fi
        sleep 1
    done

    ldapadd -x -H ldap://127.0.0.1:389 \
        -D "cn=admin,${LDAP_BASE_DN}" -w "${LDAP_ADMIN_PASSWORD}" -f "${LDAP_BASE_LDIF}"

    if [ "${AUTO_POPULATE,,}" = "true" ]; then
        bind_dn="uid=keycloak,ou=users,${LDAP_BASE_DN}"
        bind_password_hash="$(slappasswd -n -s "${KEYCLOAK_LDAP_BIND_PASSWORD}")"
        users_ldif=/tmp/users.ldif
        awk -v bind_dn="${bind_dn}" -v password_hash="${bind_password_hash}" '
            {
                line = $0
                sub(/\r$/, "", line)
            }
            line == "dn: " bind_dn { in_bind_entry = 1 }
            in_bind_entry && line ~ /^userPassword:/ {
                print "userPassword: " password_hash
                next
            }
            in_bind_entry && line == "" { in_bind_entry = 0 }
            { print }
        ' "${LDAP_USERS_LDIF}" > "${users_ldif}"

        ldapadd -x -H ldap://127.0.0.1:389 \
            -D "cn=admin,${LDAP_BASE_DN}" -w "${LDAP_ADMIN_PASSWORD}" -f "${users_ldif}"
        echo "Seed users and groups imported"
    else
        echo "AUTO_POPULATE=false; only the directory base was created"
    fi

    kill "${slapd_pid}"
    wait "${slapd_pid}" || true
else
    echo "Using existing OpenLDAP data for ${LDAP_BASE_DN}"
fi

exec slapd -f /etc/openldap/slapd.conf -h "ldap://0.0.0.0:389/" -d 0
