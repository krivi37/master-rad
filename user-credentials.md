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
| ljubo    | `Ljubo123!`   | —                |
| keycloak | `keycloak123` | admins (service) |

## Local accounts (outside the IdP — no SSO)

> Defined inside each web app, unknown to Keycloak and LDAP. Because there is no
> identity-provider session behind them, they get **no SSO**: the login lives
> only in that instance and disappears when its cookie/storage is cleared.

### Web Application A (`webapp-rti-oauth2`)

| Username      | Password | Notes                                        |
| ------------- | -------- | -------------------------------------------- |
| miroslav-local   | `local`  | Session in tab `sessionStorage`; no API token |
| milica-local     | `local`  | Session in tab `sessionStorage`; no API token |

### Web Application B (`webapp-si-saml`)

| Username    | Password | Notes                                    |
| ----------- | -------- | ---------------------------------------- |
| sonja-local   | `local`  | Session cookie only; no SAML assertion   |
| ljubo-local  | `local`  | Session cookie only; no SAML assertion   |
