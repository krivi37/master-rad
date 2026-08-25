# Koraci za ručno podešavanje — Admin portal

Portal verzija dokumenta [ManualSetupSteps.sr.md](ManualSetupSteps.sr.md).
Istih šest koraka, iste vrijednosti polja (preuzete iz `init-keycloak.sh` i
`init-federation.sh`), ali kroz Keycloak admin portal umjesto
preko `kcadm`.

Konzole (prijavite se kao `admin` / `admin`):

| Realm | Admin konzola | Native IdP protokol |
|---|---|---|
| **rti** (Keycloak A) | http://rti.localhost:8081/admin | OIDC za svoju web-aplikaciju |
| **si** (Keycloak B) | http://si.localhost:8082/admin | SAML za svoju web-aplikaciju |

Koristite **realm switcher** (padajući meni gore lijevo) da izaberete `rti` ili `si`
prije svake sekcije. Prvo podignite sistem u ručnom režimu
(`LAB_MODE=manual`, `AUTO_POPULATE=false`) sa `docker compose up -d --wait api webapp-rti-oauth2 webapp-si-saml-frontend`.

Ključne činjenice koje oblikuju ove korake:

- Grupa koja daje pristup API-ju je **`api-access`**.
- **OIDC** povjerenje = *RTI korisnici se prijavljuju na SI*. **SAML** povjerenje =
  *SI korisnici se prijavljuju na RTI*.
- API je **resource server**, a ne klijent — „podešava se“ dodavanjem audience
  mapper-a + groups claim-a na klijent `webapp-rti-oauth2`.
- Korak 6 ima **native-RTI** putanju i **federated-SI** putanju; obje su potrebne.

### Sistemski zahtijevi

- **Docker Engine** sa **Compose v2** dodatkom (`docker compose …`). Docker
  Desktop na Windows/macOS, ili Docker Engine na Linux-u.
- **PowerShell** — komande koriste PowerShell sintaksu.
- **Web pregledač** za admin konzolu; koristite novi incognito prozor pri
  testiranju federisanih prijava da izbjegnete zastarele SSO kolačiće.
- **Pristup internetu** pri prvom pokretanju radi preuzimanja image-a
  (`quay.io/keycloak/keycloak:26.0`, OpenLDAP, Node) i build-a app kontejnera.
- **~4 GB slobodne RAM memorije** i nekoliko GB diska: sistem pokreće dva Keycloak-a,
  dva OpenLDAP servera, dvije web-aplikacije i API istovremeno.
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
  razrješavaju na `127.0.0.1` (automatski na modernim OS-ovima; nije potrebna izmjena
  hosts fajla). Back-channel razrješavanje unutar kontejnera obavljaju compose
  `extra_hosts` mapiranja.

### Realm SSO session timeout-ovi (oba realm-a)

Init skripta ih postavlja na `rti` i `si`. Za svaki realm:

1. Stranica **Realm settings → Sessions**.
2. **SSO Session Idle** = `5 minutes` (300 s).
3. **SSO Session Max** = `5 minutes` (300 s).
4. **Save**.

---

## Korak 1 — Kreiranje Keycloak servisnog naloga u oba LDAP-a

Ugrađeni OpenLDAP **nema web stranicu**, pa se ovaj korak mora izvršiti kroz konzolu.
Pokrenite `ldapadd` komande ispod iz direktorijuma projekta u PowerShell-u. Svaki
Keycloak se povezuje na svoj LDAP kao `uid=keycloak,ou=users,dc=…`; lozinka mora
biti jednaka `KEYCLOAK_LDAP_BIND_PASSWORD` (podrazumijevano `keycloak123`), a nalog
se dodaje u grupu `admins`.

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

Provjerite da povezivanje (bind) kao servisni nalog radi:

```powershell
docker compose exec ldap-rti ldapwhoami -x -H ldap://localhost:389 `
  -D "uid=keycloak,ou=users,dc=rti,dc=etf,dc=bg,dc=ac,dc=rs" -w keycloak123
```

---

## Korak 2 — Keycloak LDAP federacija korisnika (+ group mapper)

Linkovi: 
 - http://rti.localhost:8081 - RTI domen
 - http://si.localhost:8082 - SI domen


Uradite ovo u **oba** realm-a; tabela navodi vrijednosti po realm-u.

### 2.1 Dodavanje LDAP provajdera

1. Realm **rti** → **User federation** → **Add LDAP providers**.
2. Popunite:

| Polje | RTI vrijednost | SI vrijednost |
|---|---|---|
| UI display name | `ldap-rti` | `ldap-si` |
| Vendor | `Other` | `Other` |
| Connection URL | `ldap://ldap-rti:389` | `ldap://ldap-si:389` |
| Bind type | `simple` | `simple` |
| Bind DN | `uid=keycloak,ou=users,dc=rti,dc=etf,dc=bg,dc=ac,dc=rs` | `uid=keycloak,ou=users,dc=si,dc=etf,dc=bg,dc=ac,dc=rs` |
| Bind credentials | `keycloak123` | `keycloak123` |
| Edit mode | `WRITABLE` | `WRITABLE` |
| Users DN | `ou=users,dc=rti,dc=etf,dc=bg,dc=ac,dc=rs` | `ou=users,dc=si,dc=etf,dc=bg,dc=ac,dc=rs` |
| Username LDAP attribute | `uid` | `uid` |
| RDN LDAP attribute | `uid` | `uid` |
| UUID LDAP attribute | `entryUUID` | `entryUUID` |
| User object classes | `inetOrgPerson, organizationalPerson, person, top` | (isto) |
| Search scope | `One Level` | `One Level` |
| Pagination | `On` | `On` |
| Import users | `On` | `On` |
| Sync registrations | `On` | `On` |

3. Kliknite **Test connection** i **Test authentication** (oba treba da budu zelena).
4. **Save**.

### 2.2 Dodavanje group mapper-a

1. Stranica **User federation** → provajder → **Mappers** → **Add mapper**.
2. **Mapper type**: `group-ldap-mapper`. Popunite:

| Polje | RTI vrijednost | SI vrijednost |
|---|---|---|
| Name | `group-mapper` | `group-mapper` |
| LDAP Groups DN | `ou=groups,dc=rti,dc=etf,dc=bg,dc=ac,dc=rs` | `ou=groups,dc=si,dc=etf,dc=bg,dc=ac,dc=rs` |
| Group Name LDAP Attribute | `cn` | `cn` |
| Group Object Classes | `groupOfNames` | `groupOfNames` |
| Preserve Group Inheritance | `Off` | `Off` |
| Membership LDAP Attribute | `member` | `member` |
| Membership Attribute Type | `DN` | `DN` |
| Membership User LDAP Attribute | `uid` | `uid` |
| Mode | `LDAP_ONLY` | `LDAP_ONLY` |
| User Groups Retrieve Strategy | `LOAD_GROUPS_BY_MEMBER_ATTRIBUTE` | (isto) |
| Drop non-existing groups during sync | `Off` | `Off` |

3. **Save**.

Ponovite 2.1–2.2 za realm **si**.

### 2.3 Kreiranje grupe `api-access` i dva korisnika po realm-u

Pošto je provajder `WRITABLE` sa uključenom Sync Registrations opcijom, grupe i
korisnici koje ovdje kreirate upisuju se nazad u LDAP. Uradite ovo u **oba** realm-a.

**Kreirajte grupu:**

1. Realm **rti** → **Groups** → **Create group** → Name `api-access` → **Create**.

**Kreirajte dva korisnika** (RTI: `miroslav`, `milica`; SI: `sonja`, `marko`):

1. **Users** → **Add user**. Popunite **Username**, **Email**, **First name**,
   **Last name**, **Email verified: On** → **Create**.

| Realm | Username | Email | First / Last | U grupi `api-access`? |
|---|---|---|---|---|
| rti | `miroslav` | `miroslav@rti.etf.bg.ac.rs` | Miroslav / Jovanovic | da |
| rti | `milica` | `milica@rti.etf.bg.ac.rs` | Milica / Krstic | ne |
| si | `sonja` | `sonja@si.etf.bg.ac.rs` | Sonja / Vuckovic | da |
| si | `marko` | `marko@si.etf.bg.ac.rs` | Marko / Kraljevic | ne |

> **Postavite lozinku nakon kreiranja svakog korisnika.** Novi korisnik nema
> kredencijale — otvorite korisnika → kartica **Credentials** → **Set password**,
> unesite lozinku, isključite **Temporary: Off** (da ne bude jednokratna lozinka),
> pa **Save**. Predložene vrijednosti: `Miroslav123!`, `Milica123!`, `Sonja123!`, `Marko123!`.

**Dodajte API korisnika u grupu:** otvorite `miroslav` (rti) / `sonja` (si) → kartica
**Groups** → **Join Group** → izaberite `api-access` → **Join**.

Ponovite 2.3 za realm **si**.

---

## Korak 3 — Povjerenje između dva identity provajdera

### 3a — OIDC: RTI korisnici se prijavljuju na SI (SI vjeruje RTI-ju)

**Na realm-u `rti`** — kreirajte broker klijent koji će SI koristiti:

1. **Clients** → **Create client** → **OpenID Connect** → Client ID `broker-si` → **Next**.
2. **Client authentication: On**; **Standard flow** označeno → **Next**.
3. **Valid redirect URIs**:
   `http://si.localhost:8082/realms/si/broker/oidc-rti/endpoint/*` → **Save**.
4. Otvorite klijent → kartica **Credentials** → kopirajte **Client secret**
   (nalijepite ga u sljedećoj sekciji; ili regenerišite i koristite tu vrijednost dosljedno).

**Na realm-u `si`** — dodajte identity provajder:

1. **Identity providers** → **Add provider** → **OpenID Connect v1.0**.
2. **Alias**: `oidc-rti` (mora da odgovara putanji redirect-a iznad).
3. **Display name**: `Login with RTI (OIDC)`.
4. **Use discovery endpoint: On** → Discovery endpoint:
   `http://rti.localhost:8081/realms/rti/.well-known/openid-configuration`
   (sačekajte zelenu kvačicu).
5. **Client authentication**: `Client secret sent as post`.
6. **Client ID**: `broker-si`; **Client secret**: nalijepite odozgo -> **Add**.
7. Nakon kreiranja podesiti **Trust email: On** 

> OIDC automatski uvozi `email`/`given_name`/`family_name` — nikakvi dodatni
> atribut mapperi nisu potrebni za ovaj smjer.

#### Opciono: `private_key_jwt` umjesto dijeljene lozinke

Umjesto kopiranja client secret-a između domena, SI može da se autentifikuje na
RTI pomoću **JWT-a potpisanog privatnim ključem svog realm-a**, koji RTI verifikuje
preko SI-jevog JWKS-a. Koraci za podešavanje (umjesto sekcije iznad):

**Na realm-u `rti`** — klijent `broker-si` (kreiran u 3a):

1. **Clients** → `broker-si` → kartica **Credentials**.
2. **Client Authenticator** → `Signed Jwt` → **Save**.
3. Kartica **Keys** → **Use JWKS URL: On** → **JWKS URL**:
   `http://si.localhost:8082/realms/si/protocol/openid-connect/certs` → **Save**.

**Na realm-u `si`** — identity provajder `oidc-rti`:

1. **Identity providers** → `oidc-rti`.
2. **Client authentication** → `JWT signed with private key`.
3. **Client assertion signature algorithm** → `RS256` (mora da odgovara klijentovom
   Signed-JWT algoritmu na RTI).
4. **Client ID**: `broker-si` (ostavite tajnu praznom) → **Save**.

> Klijent ostaje **confidential** — `private_key_jwt` je jača metoda autentifikacije
> klijenta. RTI preuzima SI-jeve ključeve za potpisivanje uživo
> sa JWKS URL-a, pa preživljava regeneraciju ključeva pri `docker compose down -v`.
>
> **Dostupnost (Reachability):** RTI dohvata JWKS URL preko `si.localhost:8082` na
> back-channel-u; taj hostname se razrješava unutar RTI kontejnera preko compose
> `extra_hosts` mapiranja — isti put koji koristi ostatak federacije.

### 3b — SAML: SI korisnici se prijavljuju na RTI (RTI vjeruje SI-ju)

**Na realm-u `rti`** — dodajte SAML identity provajder:

1. **Identity providers** → **Add provider** → **SAML v2.0**.
2. **Alias**: `saml-si`; **Display name**: `Login with SI (SAML)`.
3. **Use entity descriptor**: nalijepite
   `http://si.localhost:8082/realms/si/protocol/saml/descriptor` i dozvolite da
   uveze SSO URL i sertifikat.
4. Podesite sljedeća polja da odgovaraju automatskoj konfiguraciji, pa **Add**:

| Polje | Vrijednost |
|---|---|
| Single Sign-On Service URL | `http://si.localhost:8082/realms/si/protocol/saml` |
| Single Logout Service URL | `http://si.localhost:8082/realms/si/protocol/saml` |
| NameID policy format | `Persistent` |
| Principal type | `Subject NameID` |
| Signature algorithm | `RSA_SHA256` |

Nakon kreiranja podesiti:

| Polje | Vrijednost |
|---|---|
| HTTP-POST binding response | `On` |
| HTTP-POST binding for AuthnRequest | `On` |
| HTTP-POST binding logout | `On` |
| Want AuthnRequests signed | `Off` |
| Want Assertions signed | `Off` |
| Validate signatures | `Off` |
| Trust email | `On` |
| Sync mode | `Import`|

**Na realm-u `si`** — registrujte RTI-jev broker endpoint kao SAML klijent:

1. U pregledaču otvorite
   `http://rti.localhost:8081/realms/rti/broker/saml-si/endpoint/descriptor`
   i sačuvajte XML (to je RTI-jev **SP** metadata).
2. Realm **si** → **Clients** → **Import client** → otpremite taj XML → **Save**.
3. Otvorite uvezeni klijent i potvrdite/podesite:

| Polje | Vrijednost |
|---|---|
| Client ID | `http://rti.localhost:8081/realms/rti` |
| Valid redirect URIs / ACS POST URL | `http://rti.localhost:8081/realms/rti/broker/saml-si/endpoint` |
| Name ID format | `persistent` |
| Force POST binding | `On` |
| Sign documents | `Off` |
| Sign assertions | `Off` |

U kartici **keys**:
| Polje | Vrijednost |
|---|---|
| Client signature required | `Off` |

> Potpisi su namjerno **isključeni** kako bi par preživio `docker compose down -v`
> (realm ključevi se regenerišu).

### 3c — Odjava kod dvosmjerne federacije (mana i opcije)

**Mana:** RTI i SI se međusobno brokeruju (RTI↔SI). Ako se isti korisnik uloguje u
lancu koji obuhvata **oba** smjera (npr. na SI preko RTI-ja, pa zatim na RTI preko
SI-ja), odjava može ući u **beskonačnu petlju**: RTI prosljeđuje odjavu SI-ju, SI je
vraća RTI-ju, i tako u krug. Keycloak nema detekciju petlje za ovakav uzajamni
broker lanac.

Petlju uzrokuje **propagacija odjave** na oba IdP-a:
- `oidc-rti` (na SI) ima **Logout URL** koji pokazuje na RTI-jev `.../logout`.
- `saml-si` (na RTI) ima **Single Logout Service URL** + **HTTP-POST binding logout
  On** koji pokazuju na SI.

Izaberite jednu od dvije opcije:

**Opcija A — izolovana odjava (preporučeno, bez petlje).** Ne postavljajte
propagaciju odjave:
- `oidc-rti` (SI): **Identity providers → oidc-rti** → **Logout URL** ostavite
  **prazno** → **Save**.
- `saml-si` (RTI): **Identity providers → saml-si** → **Single Logout Service URL**
  ostavite **prazno** i **HTTP-POST binding logout → Off** → **Save**.

Kompromis: odjava iz jednog realm-a **ne** gasi SSO sesiju drugog realm-a (nema
cross-realm single logout), ali nema petlje. Odjava svake pojedinačne aplikacije
(`webapp-si-saml` ↔ SI, `webapp-rti-oauth2` ↔ RTI) i dalje radi jer koristi
sopstvene endpoint-e realm-a, a ne broker IdP odjavu.

**Opcija B — cross-realm single logout (SSO se prostire, uz rizik petlje).**
Postavite propagaciju:
- `oidc-rti` (SI): **Logout URL** =
  `http://rti.localhost:8081/realms/rti/protocol/openid-connect/logout`.
- `saml-si` (RTI): **Single Logout Service URL** =
  `http://si.localhost:8082/realms/si/protocol/saml`, **HTTP-POST binding logout → On**.

Kompromis: odjava iz jednog realm-a gasi i sesiju drugog, ali dvosmjerni lanac
(RTI→SI→RTI) može ući u opisanu petlju.

> U **preconfigured** režimu ovo kontroliše promjenljiva `KC_FEDERATION_LOGOUT_PROPAGATION`
> u `.env`: `off` (Opcija A, podrazumijevano) ili `on` (Opcija B). Skripta
> `init-federation.sh` na osnovu nje postavlja ili izostavlja gornje URL-ove.

---

## Korak 4 — SAML federacija atribut mapiranja (automatsko kreiranje federisanih korisnika)

Da bi brokerovan SI korisnik bio kreiran na RTI bez upita pri prvoj prijavi: SI SP
klijent **emituje** atribute, a RTI-jev `saml-si` IdP ih **uvozi**.

**Na realm-u `si`** — dodajte property mappere na **RTI SP klijent**
(`http://rti.localhost:8081/realms/rti`):

1. **Clients** → otvorite taj klijent → kartica **Client scopes** → kliknite na
   namjenski (dedicated) scope `http://rti.localhost:8081/realms/rti-dedicated`.
2. **Configure mapper** → **User Property** ili **Add mapper** → **By configuration** → **User Property**. Kreirajte tri:

| Name | Property | SAML Attribute Name | Name format |
|---|---|---|---|
| `email` | `email` | `email` | `Basic` |
| `firstName` | `firstName` | `firstName` | `Basic` |
| `lastName` | `lastName` | `lastName` | `Basic` |

**Na realm-u `rti`** — uvezite ih na IdP-u:

1. **Identity providers** → **Login with SI (SAML)** → kartica **Mappers** → **Add mapper**.
2. Za svaki atribut kreirajte **Attribute Importer**:

| Name | Sync mode override | Mapper type | Attribute Name | User Attribute Name |
|---|---|---|---|---|
| `email` | `Inherit` | Attribute Importer | `email` | `email` |
| `firstName` | `Inherit` | Attribute Importer | `firstName` | `firstName` |
| `lastName` | `Inherit` | Attribute Importer | `lastName` | `lastName` |

## Provjera
Probajte logovanje pomocu federisanih kredencijala na oba domena. Keycloak portal za domene se može otvoriti na sljedećim linkovima:
http://rti.localhost:8081/realms/rti/account - Login with SI (SAML)
http://si.localhost:8082/realms/si/account - Login with RTI (OIDC)

#### Opciono: ugrađeni X500 predefinisani mapperi na SI

Umjesto ručnog kreiranja tri property mapper-a, koristite Keycloak-ove ugrađene X500
mappere. Oni emituju standardna X.500 OID imena atributa sa URI formatom imena, pa
se RTI importeri poklapaju po **friendly name** umjesto po imenu u Basic formatu.

**Na realm-u `si`** — RTI SP klijent (`http://rti.localhost:8081/realms/rti`):

1. **Clients** → otvorite klijent → **Client scopes** →
   `http://rti.localhost:8081/realms/rti-dedicated` → **Mappers**.
2. **Add mapper** → **From predefined mappers** → označite **X500 email**,
   **X500 givenName**, **X500 surname** → **Add**.

Ovi mapperi mapiraju:

| Predefinisani mapper | User property | Emituje (friendly name) |
|---|---|---|
| X500 email | email | `email` |
| X500 givenName | firstName | `givenName` |
| X500 surname | lastName | `surname` |

**Na realm-u `rti`** — uvezite ih na `Login with SI (SAML)` po **Friendly Name**:

1. **Identity providers** → **saml-si** → **Mappers** → **Add mapper**.
2. Za svaki, mapper type **Attribute Importer**, ostavite **Attribute Name** prazno
   i postavite **Friendly Name**:

| Name | Sync mode override | Friendly Name | User Attribute Name |
|---|---|---|---|
| `email` | `Inherit` | `email` | `email` |
| `firstName` | `Inherit` | `givenName` | `firstName` |
| `lastName` | `Inherit` | `surname` | `lastName` |

> Kompromis: predefinisani X500 mapperi su standardno ispravni (X.500 OID-ovi) ali
> prebacuju OID/URI imenovanje na stranu importera. Mapperi u Basic formatu iznad
> poklapaju se 1:1 na obje strane i lakše se čitaju u dekodiranom SAML XML-u.

---

## Korak 5 — Klijenti za web-aplikacije i API

### 5a — OIDC klijent `webapp-rti-oauth2` (realm `rti`) + API audience

1. **Clients** → **Create client** → **OpenID Connect** → Client ID
   `webapp-rti-oauth2` → **Next**.
2. **Client authentication: Off** (javni); **Standard flow** On; **Direct access
   grants** Off → **Next**.
3. **Valid redirect URIs**: `http://localhost:3000/*`; **Web origins**:
   `http://localhost:3000` → **Save**.
4. Kartica **Advanced** → **Proof Key for Code Exchange Code Challenge Method** = `S256` → **Save**.
5. **Settings** → **Valid post logout redirect URIs**:
   `http://localhost:3000/*` → **Save**.
6. Kartica **Client scopes** → `webapp-rti-oauth2-dedicated` → **Add mapper → By
   configuration → Audience**:

| Polje | Vrijednost |
|---|---|
| Name | `oauth2-api-audience` |
| Included Custom Audience | `oauth2-api` |
| Add to access token | `On` |
| Add to ID token | `Off` |

`groups` mapper na ovom klijentu je u **Koraku 6a**.

### 5b — SAML klijent `webapp-si-saml` (realm `si`)

1. **Clients** → **Create client** → **SAML** → Client ID `webapp-si-saml` → **Next** → **Save**.
2. U **Settings** klijenta, podesite:

| Polje | Vrijednost |
|---|---|
| Name | `Web Application B (SAML SP)` |
| Valid redirect URIs | `http://localhost:4000/saml/acs` |
| Assertion Consumer Service POST Binding URL | `http://localhost:4000/saml/acs` |
| Name ID format | `username` |
| Force name ID format | `On` |
| Force POST binding | `On` |
| Include AuthnStatement | `On` |
| Front channel logout | `On` |
| Sign documents | `On` |
| Sign assertions | `On` |
| Signature algorithm | `RSA_SHA256` |

**Kartica Keys**
| Polje | Vrijednost |
|---|---|
| Client signature required | `Off` |

**Kartica Advanced**
| Polje | Vrijednost |
|---|---|
| Logout Service POST Binding URL | `http://localhost:4000/saml/sls` |
| Logout Service Redirect Binding URL | `http://localhost:4000/saml/sls` |

3. **Save**.
4. **Client scopes** → `webapp-si-saml-dedicated` → **Add mapper → By
   configuration → User Property**, tri mapper-a (istog oblika kao u Koraku 4):

| Name | User Property | SAML Attribute Name | Name format |
|---|---|---|---|
| `email` | `email` | `email` | `Basic` |
| `firstName` | `firstName` | `firstName` | `Basic` |
| `lastName` | `lastName` | `lastName` | `Basic` |


## Provjera
Probajte logovanje na web aplikacije:
http://localhost:3000 - RTI Web app
http://localhost:4000 - SI Web app

Primijetiti da na RTI Web app-u niko ne moze da pozove API na dnu stranice posto jos ne emitujemo grupe u access tokenu.

---

## Korak 6 — Group mapiranja da članovi `api-access` mogu pozivati API

### 6a — Native RTI korisnici: emitovanje `groups` claim-a

Korak 2 je već uvezao LDAP grupu `api-access` u RTI. Sada je izložite u token-u:

1. Realm **rti** → **Clients** → `webapp-rti-oauth2` → **Client scopes** →
   `webapp-rti-oauth2-dedicated` → **Add mapper → By configuration → Group Membership**.

| Polje | Vrijednost |
|---|---|
| Name | `groups` |
| Token Claim Name | `groups` |
| Full group path | `On` |
| Add to access token | `On` |
| Add to ID token | `Off` |
| Add to userinfo | `Off` |

### 6b — Federisani SI korisnici: prenos grupa kroz SAML broker

**Na realm-u `si`** — emitujte grupe sa **RTI SP klijenta**
(`http://rti.localhost:8081/realms/rti`):

1. **Clients** → taj klijent → **Client scopes** →
   `http://rti.localhost:8081/realms/rti-dedicated` → **Add mapper → By
   configuration → Group list**.

| Polje | Vrijednost |
|---|---|
| Name | `groups` |
| Group attribute name | `groups` |
| SAML Attribute NameFormat | `Basic` |
| Single Group Attribute | `On` |
| Full group path | `Off` |

*'Full group path' sadrzi i prefix domena (si). Ako bismo emitovali citavu putanju grupe, access token bi grupu emitovao kao
rti/si/api-access
i onda ne bismo mogli da pozivamo api jer api trazi clanstvo u grupi rti/api-access.

**Na realm-u `rti`** — kreirajte napredni group mapper:

1. **Identity providers** → **saml-si** → **Mappers** → **Add mapper**:

| Polje | Vrijednost |
|---|---|
| Name | `api-access-group` |
| Sync mode override | `Force` |
| Mapper type | `Advanced Attribute to Group` |
| Attributes | Key `groups`, Value `api-access` (regex `Off`) |
| Group | `/api-access` |

Dodavanjem /api-access group filtera obezbjedjujemo da se jedino ta grupa emituje u access tokene za federisane logine.

3. **Save**.

Sada brokerovan SI korisnik čiji assertion nosi `groups=api-access` biva ubačen u
`/api-access`, a klijentov mapper iz Koraka 6a ga emituje u RTI access token-u baš
kao za native korisnika.

---

## Provjera

1. **Native RTI + API** — http://localhost:3000 → **Log in with Keycloak (RTI)** →
   `miroslav` / `Miroslav123!` → **Protected API** panel vraća **200**.
2. **SI → RTI (SAML)** — http://rti.localhost:8081/realms/rti/account → **Login
   with SI (SAML)** → `sonja` / `Sonja123!` → korisnik automatski kreiran i smješten u
   `/api-access`.
3. **RTI → SI (OIDC)** — http://si.localhost:8082/realms/si/account → **Login with
   RTI (OIDC)** → `miroslav` / `Miroslav123!`.
4. U svakom realm-u, **Groups** prikazuje `api-access`, a **Identity providers**
   navodi `oidc-rti` (si) / `saml-si` (rti).

> Ako ručni korak odstupi, uskladite pomoću idempotentnih skripti:
> `docker compose run --rm -e KC_LDAP_USERS_MODE=preconfigured keycloak-init`
> i `... -e KC_FEDERATION_MODE=preconfigured keycloak-federation-init`.
