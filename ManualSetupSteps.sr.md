# Koraci za ručno podešavanje

Ovaj fajl daje korake za **ručno** podešavanje svega što laboratorija radi automatski u
*preconfigured* režimu. U preconfigured režimu dva jednokratna posla obavljaju
posao:

- `keycloak-init` (skripta: `keycloak/scripts/init-keycloak.sh`) — LDAP servisni
  nalog, Keycloak LDAP federacija korisnika + group mapper, klijenti za
  web-aplikacije/API i njihovi token mapperi, i realm SSO session timeout-ovi.
- `keycloak-federation-init` (skripta: `keycloak/scripts/init-federation.sh`) —
  OIDC i SAML povjerenje između dva Keycloak-a, SAML mapiranja atributa koja
  omogućavaju automatsko kreiranje federisanih korisnika, i propagacija API grupe
  kroz SAML broker.

Ručno izvođenje = pokrenuti stek u `LAB_MODE=manual` (uz `AUTO_POPULATE=false`
za potpuno prazan direktorijum) i izvršiti korake ispod.

Ključne činjenice koje oblikuju ove korake:

- Grupa koja daje pristup API-ju je **`api-access`**.
- **OIDC** povjerenje = *RTI korisnici se prijavljuju na SI* (SI vjeruje RTI-ju).
  **SAML** povjerenje = *SI korisnici se prijavljuju na RTI* (RTI vjeruje SI-ju).
- API **nije** Keycloak klijent — on je OAuth 2.0 *resource server*. „Podešava se“
  dodavanjem **audience mapper**-a (`oauth2-api`) i **groups** claim-a na klijent
  `webapp-rti-oauth2` kako bi API mogao da ih validira.

Sve komande ispod se izvršavaju iz direktorijuma projekta u PowerShell-u.
Komande su pisane uz pretpostavku da su kredencijali sljedeći:
 - Keycloak admin: `admin`/`admin`,
 - Servisni nalog za Keycloak u LDAP bazi: `keycloak`/`keycloak123`
 - LDAP admin lozinke `admin-rti` / `admin-si`

---

## Sistemski zahtijevi

- **Docker Engine** sa **Compose v2** dodatkom (`docker compose …`). Docker
  Desktop na Windows/macOS, ili Docker Engine na Linux-u.
- **PowerShell** — komande koriste PowerShell sintaksu.
- **Pristup internetu** pri prvom pokretanju radi preuzimanja image-a
  (`quay.io/keycloak/keycloak:26.0`, OpenLDAP, Node) i build-a app kontejnera.
- **~4 GB slobodne RAM memorije** i nekoliko GB diska: sistem pokreće dva Keycloak-a,
  dva OpenLDAP servera, dve web-aplikacije i API istovremeno.
- **Slobodni portovi na hostu**:

  | Port | Servis |
  |---|---|
  | 389 | `ldap-rti` (LDAP) |
  | 390 | `ldap-si` (LDAP) |
  | 8081 | `keycloak-rti` (RTI konzola/realm) |
  | 8082 | `keycloak-si` (SI konzola/realm) |
  | 3000 | `webapp-rti-oauth2` (OIDC SPA) |
  | 4000 | `webapp-si-saml` (SAML frontend) |
  | 5000 | `api` (OAuth 2.0 resource server) |

- **`.localhost` razrješavanje** — `rti.localhost` / `si.localhost` moraju da se
  razrješavaju na `127.0.0.1` (automatski na modernim OS-ovima; nije potrebna izjmena
  hosts fajla). Back-channel razrješavanje unutar kontejnera obavljaju compose
  `extra_hosts` mapiranja.

---

## Preduslovi

Pokrenite u ručnom režimu (prazni LDAP direktorijumi):

```powershell
# U .env: LAB_MODE=manual, AUTO_POPULATE=false, KC_LDAP_USERS_MODE=manual, KC_FEDERATION_MODE=manual
docker compose up -d --wait api webapp-rti-oauth2 webapp-si-saml-frontend
```

Autentifikujte `kcadm` unutar svakog Keycloak kontejnera (token se kešira u
kontejneru, pa ga naredni `kcadm` pozivi u istom kontejneru ponovo koriste):

```powershell
docker compose exec keycloak-rti /opt/keycloak/bin/kcadm.sh config credentials `
  --server http://localhost:8080 --realm master --user admin --password admin

docker compose exec keycloak-si /opt/keycloak/bin/kcadm.sh config credentials `
  --server http://localhost:8080 --realm master --user admin --password admin
```

Domeni `rti` i `si` već postoje (compose pokreće Keycloak sa `--import-realm`
nad praznim realm fajlom). Init skripta takođe postavlja SSO session timeout-ove
na oba realm-a, a to se ovdje može postići sa:

```powershell
docker compose exec keycloak-rti /opt/keycloak/bin/kcadm.sh update realms/rti `
  -s ssoSessionIdleTimeout=300 -s ssoSessionMaxLifespan=300

docker compose exec keycloak-si /opt/keycloak/bin/kcadm.sh update realms/si `
  -s ssoSessionIdleTimeout=300 -s ssoSessionMaxLifespan=300
```

---

## Korak 1 — Kreiranje Keycloak servisnog naloga u oba LDAP-a

Svaki Keycloak se povezuje na svoj LDAP kao `uid=keycloak,ou=users,dc=…`.
Kreirajte taj nalog (lozinka mora biti jednaka `KEYCLOAK_LDAP_BIND_PASSWORD`,
podrazumjevano `keycloak123`) i dodajte ga u grupu `admins`.

**RTI direktorijum (`ldap-rti`):**

```powershell
$ldif = @"
dn: uid=keycloak,ou=users,dc=rti,dc=etf,dc=bg,dc=ac,dc=rs
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
uid: keycloak
cn: Keycloak Service
sn: Service
mail: keycloak@rti.etf.bg.ac.rs
userPassword: keycloak123

dn: cn=admins,ou=groups,dc=rti,dc=etf,dc=bg,dc=ac,dc=rs
objectClass: top
objectClass: groupOfNames
cn: admins
member: uid=keycloak,ou=users,dc=rti,dc=etf,dc=bg,dc=ac,dc=rs
"@
$ldif | docker compose exec -T ldap-rti ldapadd -x -H ldap://localhost:389 `
  -D "cn=admin,dc=rti,dc=etf,dc=bg,dc=ac,dc=rs" -w admin-rti
```

**SI direktorijum (`ldap-si`):**

```powershell
$ldif = @"
dn: uid=keycloak,ou=users,dc=si,dc=etf,dc=bg,dc=ac,dc=rs
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
uid: keycloak
cn: Keycloak Service
sn: Service
mail: keycloak@si.etf.bg.ac.rs
userPassword: keycloak123

dn: cn=admins,ou=groups,dc=si,dc=etf,dc=bg,dc=ac,dc=rs
objectClass: top
objectClass: groupOfNames
cn: admins
member: uid=keycloak,ou=users,dc=si,dc=etf,dc=bg,dc=ac,dc=rs
"@
$ldif | docker compose exec -T ldap-si ldapadd -x -H ldap://localhost:389 `
  -D "cn=admin,dc=si,dc=etf,dc=bg,dc=ac,dc=rs" -w admin-si
```

Provjerite da servisni nalog radi:

```powershell
docker compose exec ldap-rti ldapwhoami -x -H ldap://localhost:389 `
  -D "uid=keycloak,ou=users,dc=rti,dc=etf,dc=bg,dc=ac,dc=rs" -w keycloak123
```

> Da biste imali i korisnike za prijavu i grupu `api-access`, dodajte
> `miroslav`/`milica` (RTI) i `sonja`/`marko` (SI) i grupe `api-access` na isti način —
> pogledajte `ldap-rti/users.ldif` i `ldap-si/users.ldif` za tačne unose (heševi lozinki odgovaraju lozinkama u user-credentials.md).

---

## Korak 2 — Podešavanje Keycloak LDAP federacije korisnika (+ group mapper)

Usmjerite federaciju korisnika svakog realm-a na njegov LDAP servisni nalog, zatim
dodajte group mapper tako da se LDAP `groupOfNames` grupe (npr. `api-access`)
pojave kao Keycloak grupe.

**RTI — kreiranje LDAP provajdera** (potreban je interni id realm-a kao `parentId`):

```powershell
$realmId = (docker compose exec -T keycloak-rti /opt/keycloak/bin/kcadm.sh `
  get realms/rti --fields id --format csv --noquotes).Trim()

docker compose exec keycloak-rti /opt/keycloak/bin/kcadm.sh create components -r rti `
  -s name="ldap-rti" -s providerId=ldap `
  -s providerType=org.keycloak.storage.UserStorageProvider `
  -s parentId="$realmId" `
  -s 'config.enabled=["true"]' `
  -s 'config.priority=["0"]' `
  -s 'config.editMode=["WRITABLE"]' `
  -s 'config.importEnabled=["true"]' `
  -s 'config.syncRegistrations=["true"]' `
  -s 'config.vendor=["other"]' `
  -s 'config.usernameLDAPAttribute=["uid"]' `
  -s 'config.rdnLDAPAttribute=["uid"]' `
  -s 'config.uuidLDAPAttribute=["entryUUID"]' `
  -s 'config.userObjectClasses=["inetOrgPerson,organizationalPerson,person,top"]' `
  -s 'config.connectionUrl=["ldap://ldap-rti:389"]' `
  -s 'config.usersDn=["ou=users,dc=rti,dc=etf,dc=bg,dc=ac,dc=rs"]' `
  -s 'config.authType=["simple"]' `
  -s 'config.bindDn=["uid=keycloak,ou=users,dc=rti,dc=etf,dc=bg,dc=ac,dc=rs"]' `
  -s 'config.bindCredential=["keycloak123"]' `
  -s 'config.searchScope=["1"]' `
  -s 'config.pagination=["true"]'
```

**RTI — dodavanje group mapper-a** (potreban je id komponente LDAP provajdera kao `parentId`):

```powershell
$ldapId = (docker compose exec -T keycloak-rti /opt/keycloak/bin/kcadm.sh `
  get components -r rti -q name=ldap-rti --fields id --format csv --noquotes).Trim()

docker compose exec keycloak-rti /opt/keycloak/bin/kcadm.sh create components -r rti `
  -s name=group-mapper -s providerId=group-ldap-mapper `
  -s providerType=org.keycloak.storage.ldap.mappers.LDAPStorageMapper `
  -s parentId="$ldapId" `
  -s 'config."groups.dn"=["ou=groups,dc=rti,dc=etf,dc=bg,dc=ac,dc=rs"]' `
  -s 'config."group.name.ldap.attribute"=["cn"]' `
  -s 'config."group.object.classes"=["groupOfNames"]' `
  -s 'config."preserve.group.inheritance"=["false"]' `
  -s 'config."membership.ldap.attribute"=["member"]' `
  -s 'config."membership.attribute.type"=["DN"]' `
  -s 'config."membership.user.ldap.attribute"=["uid"]' `
  -s 'config."mode"=["LDAP_ONLY"]' `
  -s 'config."user.roles.retrieve.strategy"=["LOAD_GROUPS_BY_MEMBER_ATTRIBUTE"]' `
  -s 'config."drop.non.existing.groups.during.sync"=["false"]'

# Pokreni potpunu sinhronizaciju da se korisnici/grupe odmah uvezu
docker compose exec keycloak-rti /opt/keycloak/bin/kcadm.sh `
  create "user-storage/$ldapId/sync?action=triggerFullSync" -r rti
```

**SI — isto, uz zamjenu realm-a/kontejnera/DN-a/hosta** (`si`, `keycloak-si`,
`ldap-si`, `dc=si,…`, `ldap://ldap-si:389`):

```powershell
$realmId = (docker compose exec -T keycloak-si /opt/keycloak/bin/kcadm.sh `
  get realms/si --fields id --format csv --noquotes).Trim()

docker compose exec keycloak-si /opt/keycloak/bin/kcadm.sh create components -r si `
  -s name="ldap-si" -s providerId=ldap `
  -s providerType=org.keycloak.storage.UserStorageProvider `
  -s parentId="$realmId" `
  -s 'config.enabled=["true"]' -s 'config.priority=["0"]' `
  -s 'config.editMode=["WRITABLE"]' -s 'config.importEnabled=["true"]' `
  -s 'config.syncRegistrations=["true"]' -s 'config.vendor=["other"]' `
  -s 'config.usernameLDAPAttribute=["uid"]' -s 'config.rdnLDAPAttribute=["uid"]' `
  -s 'config.uuidLDAPAttribute=["entryUUID"]' `
  -s 'config.userObjectClasses=["inetOrgPerson,organizationalPerson,person,top"]' `
  -s 'config.connectionUrl=["ldap://ldap-si:389"]' `
  -s 'config.usersDn=["ou=users,dc=si,dc=etf,dc=bg,dc=ac,dc=rs"]' `
  -s 'config.authType=["simple"]' `
  -s 'config.bindDn=["uid=keycloak,ou=users,dc=si,dc=etf,dc=bg,dc=ac,dc=rs"]' `
  -s 'config.bindCredential=["keycloak123"]' `
  -s 'config.searchScope=["1"]' -s 'config.pagination=["true"]'

$ldapId = (docker compose exec -T keycloak-si /opt/keycloak/bin/kcadm.sh `
  get components -r si -q name=ldap-si --fields id --format csv --noquotes).Trim()

docker compose exec keycloak-si /opt/keycloak/bin/kcadm.sh create components -r si `
  -s name=group-mapper -s providerId=group-ldap-mapper `
  -s providerType=org.keycloak.storage.ldap.mappers.LDAPStorageMapper `
  -s parentId="$ldapId" `
  -s 'config."groups.dn"=["ou=groups,dc=si,dc=etf,dc=bg,dc=ac,dc=rs"]' `
  -s 'config."group.name.ldap.attribute"=["cn"]' `
  -s 'config."group.object.classes"=["groupOfNames"]' `
  -s 'config."preserve.group.inheritance"=["false"]' `
  -s 'config."membership.ldap.attribute"=["member"]' `
  -s 'config."membership.attribute.type"=["DN"]' `
  -s 'config."membership.user.ldap.attribute"=["uid"]' `
  -s 'config."mode"=["LDAP_ONLY"]' `
  -s 'config."user.roles.retrieve.strategy"=["LOAD_GROUPS_BY_MEMBER_ATTRIBUTE"]' `
  -s 'config."drop.non.existing.groups.during.sync"=["false"]'

docker compose exec keycloak-si /opt/keycloak/bin/kcadm.sh `
  create "user-storage/$ldapId/sync?action=triggerFullSync" -r si
```

### 2.3 Kreiranje grupe `api-access` i dva korisnika po realm-u

Pošto je provajder `WRITABLE` sa uključenom Sync Registrations opcijom,
korisnici/grupe kreirani u Keycloak-u se upisuju nazad u LDAP. Kreirajte grupu
`api-access` i dva korisnika u svakom realm-u.

**RTI — grupa + korisnici** (`miroslav` dobija pristup API-ju, `milica` ne):

```powershell
# grupa api-access
docker compose exec keycloak-rti /opt/keycloak/bin/kcadm.sh create groups -r rti -s name=api-access

# miroslav
docker compose exec keycloak-rti /opt/keycloak/bin/kcadm.sh create users -r rti `
  -s username=miroslav -s enabled=true -s email=miroslav@rti.etf.bg.ac.rs `
  -s firstName=Miroslav -s lastName=Jovanovic
docker compose exec keycloak-rti /opt/keycloak/bin/kcadm.sh set-password -r rti `
  --username miroslav -p 'Miroslav123!'

# milica
docker compose exec keycloak-rti /opt/keycloak/bin/kcadm.sh create users -r rti `
  -s username=milica -s enabled=true -s email=milica@rti.etf.bg.ac.rs `
  -s firstName=Milica -s lastName=Krstic
docker compose exec keycloak-rti /opt/keycloak/bin/kcadm.sh set-password -r rti `
  --username milica -p 'Milica123!'

# Dodaj miroslav u api-access
$miroslavId = (docker compose exec -T keycloak-rti /opt/keycloak/bin/kcadm.sh `
  get users -r rti -q username=miroslav --fields id --format csv --noquotes).Trim()
$groupId = (docker compose exec -T keycloak-rti /opt/keycloak/bin/kcadm.sh `
  get groups -r rti -q search=api-access --fields id --format csv --noquotes).Trim()
docker compose exec keycloak-rti /opt/keycloak/bin/kcadm.sh `
  update "users/$miroslavId/groups/$groupId" -r rti -s realm=rti -s userId="$miroslavId" -s groupId="$groupId" -n
```

**SI — grupa + korisnici** (`sonja` dobija pristup API-ju, `marko` ne):

```powershell
docker compose exec keycloak-si /opt/keycloak/bin/kcadm.sh create groups -r si -s name=api-access

docker compose exec keycloak-si /opt/keycloak/bin/kcadm.sh create users -r si `
  -s username=sonja -s enabled=true -s email=sonja@si.etf.bg.ac.rs `
  -s firstName=Sonja -s lastName=Vuckovic
docker compose exec keycloak-si /opt/keycloak/bin/kcadm.sh set-password -r si `
  --username sonja -p 'Sonja123!'

docker compose exec keycloak-si /opt/keycloak/bin/kcadm.sh create users -r si `
  -s username=marko -s enabled=true -s email=marko@si.etf.bg.ac.rs `
  -s firstName=Marko -s lastName=Kraljevic
docker compose exec keycloak-si /opt/keycloak/bin/kcadm.sh set-password -r si `
  --username marko -p 'Marko123!'

$sonjaId = (docker compose exec -T keycloak-si /opt/keycloak/bin/kcadm.sh `
  get users -r si -q username=sonja --fields id --format csv --noquotes).Trim()
$groupId = (docker compose exec -T keycloak-si /opt/keycloak/bin/kcadm.sh `
  get groups -r si -q search=api-access --fields id --format csv --noquotes).Trim()
docker compose exec keycloak-si /opt/keycloak/bin/kcadm.sh `
  update "users/$sonjaId/groups/$groupId" -r si -s realm=si -s userId="$sonjaId" -s groupId="$groupId" -n
```

Provjerite da su unosi upisani u LDAP:

```powershell
docker compose exec ldap-rti ldapsearch -x -H ldap://localhost:389 `
  -D "cn=admin,dc=rti,dc=etf,dc=bg,dc=ac,dc=rs" -w admin-rti `
  -b "dc=rti,dc=etf,dc=bg,dc=ac,dc=rs" "(|(uid=miroslav)(uid=milica)(cn=api-access))"
```

---

## Korak 3 — Podešavanje povjerenja između dva pružaoca identiteta

Preduslov: compose `extra_hosts` mapiranja čine da se `rti.localhost` /
`si.localhost` razrješavaju **unutar** kontejnera, tako da back-channel pozivi rade.

### 3a — OIDC: RTI korisnici se prijavljuju na SI (SI veruje RTI-ju)

**Na RTI** — povjerljivi (confidential) klijent `broker-si` kojim se SI autentifikuje:

```powershell
docker compose exec keycloak-rti /opt/keycloak/bin/kcadm.sh create clients -r rti `
  -s clientId=broker-si -s enabled=true -s protocol=openid-connect `
  -s publicClient=false -s secret=broker-si-secret `
  -s standardFlowEnabled=true -s directAccessGrantsEnabled=false `
  -s 'redirectUris=["http://si.localhost:8082/realms/si/broker/oidc-rti/endpoint/*"]'
```

**Na SI** — OIDC identity provajder `oidc-rti` koji pokazuje nazad na RTI:

```powershell
docker compose exec keycloak-si /opt/keycloak/bin/kcadm.sh `
  create identity-provider/instances -r si `
  -s alias=oidc-rti -s displayName="Login with RTI (OIDC)" `
  -s providerId=oidc -s enabled=true -s trustEmail=true -s storeToken=false `
  -s config.clientId=broker-si -s config.clientSecret=broker-si-secret `
  -s config.clientAuthMethod=client_secret_post `
  -s config.issuer="http://rti.localhost:8081/realms/rti" `
  -s config.authorizationUrl="http://rti.localhost:8081/realms/rti/protocol/openid-connect/auth" `
  -s config.tokenUrl="http://rti.localhost:8081/realms/rti/protocol/openid-connect/token" `
  -s config.userInfoUrl="http://rti.localhost:8081/realms/rti/protocol/openid-connect/userinfo" `
  -s config.logoutUrl="http://rti.localhost:8081/realms/rti/protocol/openid-connect/logout" `
  -s config.jwksUrl="http://rti.localhost:8081/realms/rti/protocol/openid-connect/certs" `
  -s config.useJwksUrl=true -s config.validateSignature=true `
  -s 'config.defaultScope=openid profile email' -s config.syncMode=IMPORT
```

> Generički OIDC broker već uvozi `email`/`given_name`/`family_name`, pa OIDC smjer
> ne zahteva **nikakva** dodatna mapiranja atributa.

#### Opciono: `private_key_jwt` umjesto dijeljene lozinke

Realističnije od dijeljene lozinke: SI se autentifikuje na RTI pomoću **JWT-a
potpisanog privatnim ključem SI realm-a**, a RTI ga verifikuje preko SI-jevog
objavljenog JWKS-a. Koristite ovo **umjesto** dva bloka iznad.

**Na RTI** — klijent `broker-si` koristi Signed-JWT autentifikaciju i vjeruje SI-jevom JWKS-u:

```powershell
docker compose exec keycloak-rti /opt/keycloak/bin/kcadm.sh create clients -r rti `
  -s clientId=broker-si -s enabled=true -s protocol=openid-connect `
  -s publicClient=false -s clientAuthenticatorType=client-jwt `
  -s standardFlowEnabled=true -s directAccessGrantsEnabled=false `
  -s 'redirectUris=["http://si.localhost:8082/realms/si/broker/oidc-rti/endpoint/*"]' `
  -s 'attributes."use.jwks.url"=true' `
  -s 'attributes."jwks.url"="http://si.localhost:8082/realms/si/protocol/openid-connect/certs"' `
  -s 'attributes."token.endpoint.auth.signing.alg"=RS256'
```

**Na SI** — IdP `oidc-rti` potpisuje client assertion svojim privatnim ključem
(obratite pažnju na `clientAuthMethod=private_key_jwt` i **bez** `clientSecret`):

```powershell
docker compose exec keycloak-si /opt/keycloak/bin/kcadm.sh `
  create identity-provider/instances -r si `
  -s alias=oidc-rti -s displayName="Login with RTI (OIDC)" `
  -s providerId=oidc -s enabled=true -s trustEmail=true -s storeToken=false `
  -s config.clientId=broker-si `
  -s config.clientAuthMethod=private_key_jwt `
  -s config.clientAssertionSigningAlg=RS256 `
  -s config.issuer="http://rti.localhost:8081/realms/rti" `
  -s config.authorizationUrl="http://rti.localhost:8081/realms/rti/protocol/openid-connect/auth" `
  -s config.tokenUrl="http://rti.localhost:8081/realms/rti/protocol/openid-connect/token" `
  -s config.userInfoUrl="http://rti.localhost:8081/realms/rti/protocol/openid-connect/userinfo" `
  -s config.logoutUrl="http://rti.localhost:8081/realms/rti/protocol/openid-connect/logout" `
  -s config.jwksUrl="http://rti.localhost:8081/realms/rti/protocol/openid-connect/certs" `
  -s config.useJwksUrl=true -s config.validateSignature=true `
  -s 'config.defaultScope=openid profile email' -s config.syncMode=IMPORT
```

> `private_key_jwt` je jača metoda autentifikacije klijenta. RTI vjeruje SI-jevom potpisu jer
> `jwks.url` pokazuje na SI-jeve realm sertifikate; `docker compose down -v`
> regeneriše te ključeve, ali se JWKS URL preuzima uživo, pa ostaje otporno na reset.
>
> Algoritam potpisivanja mora da se poklapa na obje strane (`RS256` ovde): klijentov
> `token.endpoint.auth.signing.alg` na RTI i `clientAssertionSigningAlg` na SI IdP-u.
>
> **Dostupnost (Reachability):** RTI preuzima `jwks.url` preko `si.localhost:8082`
> na back-channel-u; taj hostname se razrješava unutar RTI kontejnera preko compose
> `extra_hosts` mapiranja — isti put koji koristi ostatak federacije.

Provjerite da obje strane fiksiraju isti algoritam:

```powershell
# RTI klijent — očekuje se "token.endpoint.auth.signing.alg":"RS256"
docker compose exec keycloak-rti /opt/keycloak/bin/kcadm.sh `
  get clients -r rti -q clientId=broker-si --fields id,attributes

# SI IdP — očekuje se "clientAssertionSigningAlg":"RS256"
docker compose exec keycloak-si /opt/keycloak/bin/kcadm.sh `
  get "identity-provider/instances/oidc-rti" -r si --fields config
```

Neusklađenost se pri prijavi pojavljuje kao `invalid_client` u RTI logu:

```powershell
docker compose logs keycloak-rti --tail 100 | Select-String -Pattern "invalid_client|client assertion|signature"
```

### 3b — SAML: SI korisnici se prijavljuju na RTI (RTI vjeruje SI-ju)

**Na RTI** — SAML pružaoc identiteta `saml-si` koji pokazuje na SI:

```powershell
docker compose exec keycloak-rti /opt/keycloak/bin/kcadm.sh `
  create identity-provider/instances -r rti `
  -s alias=saml-si -s displayName="Login with SI (SAML)" `
  -s providerId=saml -s enabled=true -s trustEmail=true `
  -s config.singleSignOnServiceUrl="http://si.localhost:8082/realms/si/protocol/saml" `
  -s config.singleLogoutServiceUrl="http://si.localhost:8082/realms/si/protocol/saml" `
  -s config.nameIDPolicyFormat="urn:oasis:names:tc:SAML:2.0:nameid-format:persistent" `
  -s config.postBindingResponse=true -s config.postBindingAuthnRequest=true `
  -s config.postBindingLogout=true `
  -s config.wantAuthnRequestsSigned=false -s config.wantAssertionsSigned=false `
  -s config.validateSignature=false -s config.signatureAlgorithm=RSA_SHA256 `
  -s config.principalType=SUBJECT -s config.syncMode=IMPORT
```

**Na SI** — registrujte RTI-jev broker endpoint kao SAML SP klijent. clientId je
bazni URL RTI realm-a; njegov ACS je broker endpoint:

```powershell
docker compose exec keycloak-si /opt/keycloak/bin/kcadm.sh create clients -r si `
  -s clientId="http://rti.localhost:8081/realms/rti" `
  -s name="RTI broker (SAML SP)" -s enabled=true -s protocol=saml `
  -s 'redirectUris=["http://rti.localhost:8081/realms/rti/broker/saml-si/endpoint"]' `
  -s 'attributes."saml.authnstatement"=true' `
  -s 'attributes."saml.server.signature"=false' `
  -s 'attributes."saml.assertion.signature"=false' `
  -s 'attributes."saml.client.signature"=false' `
  -s 'attributes."saml.force.post.binding"=true' `
  -s 'attributes."saml_name_id_format"=persistent' `
  -s 'attributes."saml_assertion_consumer_url_post"="http://rti.localhost:8081/realms/rti/broker/saml-si/endpoint"' `
  -s 'attributes."saml_single_logout_service_url_post"="http://rti.localhost:8081/realms/rti/broker/saml-si/endpoint"'
```

> Potpisi su namjerno **isključeni** na SAML paru kako bi konfiguracija preživjela
> `docker compose down -v` (koji regeneriše realm ključeve za potpisivanje).

> **Mana odjave kod federacije i opcije.** Gornji `oidc-rti` `config.logoutUrl` i
> `saml-si` `config.singleLogoutServiceUrl` / `postBindingLogout` uključuju
> **cross-realm single logout (Opcija B)**. Pošto RTI i SI brokeruju jedan drugog,
> korisnik čija sesija ulanči oba smjera (na SI preko RTI, pa na RTI preko SI) može
> ući u **beskonačnu petlju odjave**. Da to izbjegnete (**Opcija A**, preporučeno),
> kreirajte IdP-ove sa praznim `config.logoutUrl=` (oidc-rti) i praznim
> `config.singleLogoutServiceUrl=` + `config.postBindingLogout=false` (saml-si);
> gubite cross-realm SLO ali odjava svake aplikacije i dalje radi. U preconfigured
> režimu koristite `KC_FEDERATION_LOGOUT_PROPAGATION` u `.env`
> (`off` = Opcija A podrazumijevano, `on` = Opcija B). Vidjeti `ManualSetupPortal.sr.md` §3c.

---

## Korak 4 — SAML federacija, mapiranje atributa (automatsko kreiranje federisanih korisnika)

SAML assertion podrazumijevano nosi samo NameID, pa bi federisani SI korisnik dospeo
na RTI-jevu formu za prvu prijavu sa praznim poljima i tražio bi se ručni unos. To se rješava tako što SI
SP klijent **emituje** `email`/`firstName`/`lastName` kao atribute, a RTI
`saml-si` IdP ih **uvozi** u profil korisnika — tako se korisnik kreira bez ikakvog
ručnog unosa.

**Na SI** — dodajte property mappere na RTI SP klijent (prvo dobavite njegov UUID):

```powershell
$spUuid = (docker compose exec -T keycloak-si /opt/keycloak/bin/kcadm.sh `
  get clients -r si -q clientId="http://rti.localhost:8081/realms/rti" `
  --fields id --format csv --noquotes).Trim()

foreach ($m in @(@('email','email'), @('firstName','firstName'), @('lastName','lastName'))) {
  docker compose exec keycloak-si /opt/keycloak/bin/kcadm.sh `
    create "clients/$spUuid/protocol-mappers/models" -r si `
    -s name="$($m[0])" -s protocol=saml `
    -s protocolMapper=saml-user-property-mapper `
    -s "config.`"user.attribute`"=$($m[1])" `
    -s "config.`"attribute.name`"=$($m[0])" `
    -s 'config."attribute.nameformat"=Basic' `
    -s "config.`"friendly.name`"=$($m[0])"
}
```

**Na RTI** — uvezite te atribute na `saml-si` IdP-u:

```powershell
foreach ($m in @(@('email','email'), @('firstName','firstName'), @('lastName','lastName'))) {
  docker compose exec keycloak-rti /opt/keycloak/bin/kcadm.sh `
    create "identity-provider/instances/saml-si/mappers" -r rti `
    -s name="$($m[0])" -s identityProviderAlias=saml-si `
    -s identityProviderMapper=saml-user-attribute-idp-mapper `
    -s 'config."syncMode"=INHERIT' `
    -s "config.`"attribute.name`"=$($m[0])" `
    -s "config.`"user.attribute`"=$($m[1])"
}
```

#### Opciono: ugrađeni X500 predefinisani mapperi na SI

Umjesto ručnog kreiranja tri property mapper-a, dodajte Keycloak-ove ugrađene
**X500 email / givenName / surname** mappere na SI SP klijent. Oni emituju
standardna LDAP/X.500 OID imena atributa (`urn:oid:…`) sa URI formatom imena, pa se
RTI uvoznici moraju poklapati po **friendly name** umjesto po imenu u Basic formatu.
Koristite ovo **umjesto** dva bloka iznad.

**Na SI** — prikačite predefinisane mappere na RTI SP klijent. Keycloak ih seeduje
pod ugrađenim client scope-om `saml_organization`; kopirajte ih na namjenski
scope klijenta:

```powershell
$spUuid = (docker compose exec -T keycloak-si /opt/keycloak/bin/kcadm.sh `
  get clients -r si -q clientId="http://rti.localhost:8081/realms/rti" `
  --fields id --format csv --noquotes).Trim()

# name | user.attribute | urn:oid ime atributa | friendly name
$x500 = @(
  @('X500 email',     'email',     'urn:oid:1.2.840.113549.1.9.1', 'email'),
  @('X500 givenName', 'firstName', 'urn:oid:2.5.4.42',             'givenName'),
  @('X500 surname',   'lastName',  'urn:oid:2.5.4.4',              'surname')
)
foreach ($m in $x500) {
  docker compose exec keycloak-si /opt/keycloak/bin/kcadm.sh `
    create "clients/$spUuid/protocol-mappers/models" -r si `
    -s name="$($m[0])" -s protocol=saml `
    -s protocolMapper=saml-user-property-mapper `
    -s "config.`"user.attribute`"=$($m[1])" `
    -s "config.`"attribute.name`"=$($m[2])" `
    -s 'config."attribute.nameformat"=URI Reference' `
    -s "config.`"friendly.name`"=$($m[3])"
}
```

**Na RTI** — uvezite ih na `saml-si` po **friendly name** (da ne zavisite od OID stringa):

```powershell
# friendly name | user attribute
$imp = @(@('email','email'), @('givenName','firstName'), @('surname','lastName'))
foreach ($m in $imp) {
  docker compose exec keycloak-rti /opt/keycloak/bin/kcadm.sh `
    create "identity-provider/instances/saml-si/mappers" -r rti `
    -s name="$($m[0])" -s identityProviderAlias=saml-si `
    -s identityProviderMapper=saml-user-attribute-idp-mapper `
    -s 'config."syncMode"=INHERIT' `
    -s "config.`"friendly.name`"=$($m[0])" `
    -s "config.`"user.attribute`"=$($m[1])"
}
```

> Kompromis: predefinisani X500 mapperi su standardno ispravni (X.500 OID-ovi) ali
> prebacuju OID/URI imenovanje na stranu uvoznika. Mapperi u Basic formatu
> `email`/`firstName`/`lastName` iznad poklapaju se 1:1 na obe strane i lakše se
> čitaju u dekodiranom SAML XML-u.

---

## Korak 5 — Podešavanje klijenata za web-aplikacije i API

- **`webapp-rti-oauth2`** — javni OIDC klijent u **RTI** (Authorization Code + PKCE).
- **`webapp-si-saml`** — SAML klijent (SP) u **SI**.
- **API** — nema sopstvenog klijenta; validira `oauth2-api` audience i `groups`
  claim koje RTI upisuje u `webapp-rti-oauth2` access token-e (dodato ovje kao
  mapperi; strana sa `groups` vrednošću je Korak 6).

### 5a — OIDC klijent `webapp-rti-oauth2` (RTI) + API audience mapper

```powershell
docker compose exec keycloak-rti /opt/keycloak/bin/kcadm.sh create clients -r rti `
  -s clientId=webapp-rti-oauth2 -s enabled=true -s protocol=openid-connect `
  -s publicClient=true -s standardFlowEnabled=true -s directAccessGrantsEnabled=false `
  -s 'redirectUris=["http://localhost:3000/*"]' `
  -s 'webOrigins=["http://localhost:3000"]' `
  -s 'attributes."pkce.code.challenge.method"=S256' `
  -s 'attributes."post.logout.redirect.uris"="http://localhost:3000/*"'

# Dohvati UUID klijenta za njegove mappere
$appUuid = (docker compose exec -T keycloak-rti /opt/keycloak/bin/kcadm.sh `
  get clients -r rti -q clientId=webapp-rti-oauth2 --fields id --format csv --noquotes).Trim()

# Audience mapper: upiši "oauth2-api" u access token da bi ga API prihvatio
docker compose exec keycloak-rti /opt/keycloak/bin/kcadm.sh `
  create "clients/$appUuid/protocol-mappers/models" -r rti `
  -s name=oauth2-api-audience -s protocol=openid-connect `
  -s protocolMapper=oidc-audience-mapper `
  -s 'config."included.custom.audience"=oauth2-api' `
  -s 'config."access.token.claim"=true' `
  -s 'config."id.token.claim"=false'
```

`groups` membership mapper na ovom istom klijentu je u **Koraku 6** (to je
native-RTI polovina API autorizacije).

### 5b — SAML klijent `webapp-si-saml` (SI) + njegovi property mapperi

```powershell
docker compose exec keycloak-si /opt/keycloak/bin/kcadm.sh create clients -r si `
  -s clientId=webapp-si-saml -s name="Web Application B (SAML SP)" `
  -s enabled=true -s protocol=saml -s frontchannelLogout=true `
  -s 'redirectUris=["http://localhost:4000/saml/acs"]' `
  -s 'attributes."saml.authnstatement"=true' `
  -s 'attributes."saml.server.signature"=true' `
  -s 'attributes."saml.assertion.signature"=true' `
  -s 'attributes."saml.client.signature"=false' `
  -s 'attributes."saml.encrypt"=false' `
  -s 'attributes."saml.force.post.binding"=true' `
  -s 'attributes."saml.signature.algorithm"=RSA_SHA256' `
  -s 'attributes."saml_name_id_format"=username' `
  -s 'attributes."saml_force_name_id_format"=true' `
  -s 'attributes."saml_assertion_consumer_url_post"="http://localhost:4000/saml/acs"' `
  -s 'attributes."saml_single_logout_service_url_post"="http://localhost:4000/saml/sls"' `
  -s 'attributes."saml_single_logout_service_url_redirect"="http://localhost:4000/saml/sls"'

# Emituj email/firstName/lastName ka SP-u da welcome prikaz ima atribute
$appUuid = (docker compose exec -T keycloak-si /opt/keycloak/bin/kcadm.sh `
  get clients -r si -q clientId=webapp-si-saml --fields id --format csv --noquotes).Trim()

foreach ($m in @(@('email','email'), @('firstName','firstName'), @('lastName','lastName'))) {
  docker compose exec keycloak-si /opt/keycloak/bin/kcadm.sh `
    create "clients/$appUuid/protocol-mappers/models" -r si `
    -s name="$($m[0])" -s protocol=saml `
    -s protocolMapper=saml-user-property-mapper `
    -s "config.`"user.attribute`"=$($m[1])" `
    -s "config.`"attribute.name`"=$($m[0])" `
    -s 'config."attribute.nameformat"=Basic' `
    -s "config.`"friendly.name`"=$($m[0])"
}
```

---

## Korak 6 — Group mapiranja da članovi `api-access` mogu pozivati API

API prihvata token samo kada nosi audience `oauth2-api` **i** `groups` claim koji
sadrži `api-access`. To mora da radi za **native RTI korisnike** i za **korisnike
federisane iz SI** — dvije odvojene putanje.

### 6a — RTI korisnici: emitovanje `groups` claim-a na `webapp-rti-oauth2`

LDAP group mapper iz Koraka 2 je već uvezao `api-access` u RTI. Sada dodajte
group-membership mapper na klijent da bi bio prisutan u access tokenu:

```powershell
$appUuid = (docker compose exec -T keycloak-rti /opt/keycloak/bin/kcadm.sh `
  get clients -r rti -q clientId=webapp-rti-oauth2 --fields id --format csv --noquotes).Trim()

docker compose exec keycloak-rti /opt/keycloak/bin/kcadm.sh `
  create "clients/$appUuid/protocol-mappers/models" -r rti `
  -s name=groups -s protocol=openid-connect `
  -s protocolMapper=oidc-group-membership-mapper `
  -s 'config."claim.name"=groups' `
  -s 'config."full.path"=true' `
  -s 'config."access.token.claim"=true' `
  -s 'config."id.token.claim"=false' `
  -s 'config."userinfo.token.claim"=false'
```

### 6b — Federisani SI korisnici: prenos članstva u grupi kroz SAML broker

Tri dijela: SI SP klijent **emituje** korisnikove grupe kao jedan SAML atribut; RTI
ima **realm grupu** `api-access`; i `saml-si` IdP ima **napredni group mapper**
(advanced group mapper) koji ubacuje brokerovane korisnike u `/api-access` kada
njihov assertion kaže `groups=api-access`. Kada je jednom u toj realm grupi,
klijentov mapper iz Koraka 6a upisuje `api-access` u token baš kao za domaćeg korisnika.

**Na SI** — group-membership mapper na RTI SP klijentu:

```powershell
$spUuid = (docker compose exec -T keycloak-si /opt/keycloak/bin/kcadm.sh `
  get clients -r si -q clientId="http://rti.localhost:8081/realms/rti" `
  --fields id --format csv --noquotes).Trim()

docker compose exec keycloak-si /opt/keycloak/bin/kcadm.sh `
  create "clients/$spUuid/protocol-mappers/models" -r si `
  -s name=groups -s protocol=saml `
  -s protocolMapper=saml-group-membership-mapper `
  -s 'config."attribute.name"=groups' `
  -s 'config."attribute.nameformat"=Basic' `
  -s 'config."single"=true' `
  -s 'config."full.path"=false'
```

**Na RTI** — kreirajte realm grupu, zatim napredni group IdP mapper:

```powershell
docker compose exec keycloak-rti /opt/keycloak/bin/kcadm.sh `
  create groups -r rti -s name=api-access

# Napredni group mapper: FORCE ponovo procenjuje pri svakoj prijavi. Koristi JSON telo.
$json = @"
{
  "name": "api-access-group",
  "identityProviderAlias": "saml-si",
  "identityProviderMapper": "saml-advanced-group-idp-mapper",
  "config": {
    "syncMode": "FORCE",
    "are.attribute.values.regex": "false",
    "attributes": "[{\"key\":\"groups\",\"value\":\"api-access\"}]",
    "group": "/api-access"
  }
}
"@
$json | docker compose exec -T keycloak-rti /opt/keycloak/bin/kcadm.sh `
  create "identity-provider/instances/saml-si/mappers" -r rti -f -
```

---

## Provjera

```powershell
# Native RTI korisnik sa pristupom API-ju (iz webapp-rti-oauth2 na http://localhost:3000)
#   prijava kao miroslav / Miroslav123!  -> Protected API panel vraća 200
#
# Federisani SI korisnik preko SAML-a u RTI:
#   http://rti.localhost:8081/realms/rti/account -> "Login with SI (SAML)"
#   prijava kao sonja / Sonja123!  -> korisnik automatski kreiran, dospijeva u /api-access
#
# Federisani RTI korisnik preko OIDC-a u SI:
#   http://si.localhost:8082/realms/si/account -> "Login with RTI (OIDC)"
#   prijava kao miroslav / Miroslav123!

# Potvrdi da je LDAP grupa stigla u RTI
docker compose exec keycloak-rti /opt/keycloak/bin/kcadm.sh get groups -r rti

# Potvrdi da oba identity provajdera postoje
docker compose exec keycloak-si  /opt/keycloak/bin/kcadm.sh get identity-provider/instances -r si  --fields alias
docker compose exec keycloak-rti /opt/keycloak/bin/kcadm.sh get identity-provider/instances -r rti --fields alias
```

> Savjet: automatske skripte su idempotentne i predstavljaju izvor istine. Ako
> ručni korak odstupi, pokrenite `docker compose run --rm -e KC_LDAP_USERS_MODE=preconfigured keycloak-init`
> ili `... -e KC_FEDERATION_MODE=preconfigured keycloak-federation-init` da uskladite.
