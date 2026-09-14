# Korisnički pristupni podaci za laboratoriju

> Lozinke za unaprijed kreirane LDAP korisnike.
> U LDIF fajlovima čuvaju se samo SSHA heš vrijednosti ovih lozinki.

## RTI direktorijum (`ldap-rti`, domen `rti`)

| Korisničko ime | Lozinka      | Grupe            |
| -------- | ------------ | ---------------- |
| miroslav | `Miroslav123!` | api-access       |
| milica   | `Milica123!`   | —                |
| keycloak | `keycloak123` | admins (servis)  |

## SI direktorijum (`ldap-si`, domen `si`)

| Korisničko ime | Lozinka      | Grupe            |
| -------- | ------------ | ---------------- |
| sonja    | `Sonja123!`   | api-access       |
| ljubo    | `Ljubo123!`   | —                |
| keycloak | `keycloak123` | admins (servis)  |

## Lokalni nalozi (izvan IdP-a — bez SSO)

> Definisani su unutar svake veb-aplikacije i nisu poznati Keycloaku ni LDAP-u.
> Pošto iza njih ne postoji sesija pružaoca identiteta, **nemaju SSO**: prijava postoji
> samo u toj instanci i nestaje kada se izbrišu njeni kolačići ili podaci iz lokalnog skladišta.

### Veb-aplikacija A (`webapp-rti-oauth2`)

| Korisničko ime | Lozinka | Napomene                                      |
| ------------- | -------- | -------------------------------------------- |
| miroslav-local   | `local`  | Sesija u kartici, u `sessionStorage`; bez API tokena |
| milica-local     | `local`  | Sesija u kartici, u `sessionStorage`; bez API tokena |

### Veb-aplikacija B (`webapp-si-saml`)

| Korisničko ime | Lozinka | Napomene                             |
| ----------- | -------- | ---------------------------------------- |
| sonja-local   | `local`  | Samo kolačić sesije; bez SAML assertion-a    |
| ljubo-local  | `local`  | Samo kolačić sesije; bez SAML assertion-a   |
