# Lab User Credentials

> Plaintext passwords for the seeded LDAP users. **Lab use only — do not use in production.**
> The LDIF files store only salted SSHA hashes of these passwords.

## RTI directory (`ldap-rti`, realm `rti`)

| Username | Password     | Groups           |
| -------- | ------------ | ---------------- |
| miroslav | `Miroslav123!` | api-access       |
| milica   | `Milica123!`   | —                |
| keycloak | `keycloak123` | admins (service) |

## SI directory (`ldap-si`, realm `si`)

| Username | Password     | Groups           |
| -------- | ------------ | ---------------- |
| sonja    | `Sonja123!`   | api-access       |
| marko    | `Marko123!`   | —                |
| keycloak | `keycloak123` | admins (service) |
