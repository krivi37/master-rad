# Sistemski zahtjevi

- Docker Engine, na primjer Docker Desktop na Windows-u
- Slobodni portovi na hostu: 389, 390, 8081, 8082, 3000, 4000, 5000, kao i
  uzastopni portovi od 3001 i 4001 za tražene dodatne instance web-aplikacija

# Brzi početak (unaprijed podešeni režim)

1. Kreirajte `.env` fajl u korjenskom direktorijumu.
2. Kopirajte sadržaj fajla `.env.example` u `.env` fajl.
3. Postavite sljedeće vrijednosti:
  a. `LAB_MODE=preconfigured`
  b. Izmijenite lozinke za `LDAP_RTI_ADMIN_PASSWORD`, `LDAP_SI_ADMIN_PASSWORD`, `KEYCLOAK_ADMIN_PASSWORD` i `KEYCLOAK_LDAP_BIND_PASSWORD`.
4. Pokrenite Docker Desktop ili Docker servis.
5. Iz korjenskog direktorijuma pokrenite `lab-up` skriptu (`lab-up.sh` za Linux
  ili `lab-up.ps1` za Windows). Parametri predstavljaju ukupan broj instanci
  RTI i SI aplikacije, uključujući osnovnu instancu. Na primjer,
  `./lab-up.sh 2 2` pokreće dvije RTI i dvije SI instance, dok `1 1` pokreće samo
  osnovne instance bez dodatnih kopija.

Sada možete pristupiti različitim adresama preko pretrazivaca:

1. http://rti.localhost:8081 - Keycloak instanca za RTI realm; za prijavu koristite Keycloak administratorske kredencijale.
2. http://si.localhost:8082 - Isto, samo za SI realm.
3. http://rti.localhost:8081/realms/rti/account i http://si.localhost:8082/realms/si/account - ovdje se možete prijaviti kredencijalima korisnika koji nisu administratori; sve korisnike možete pronaći u fajlu `user-credentials.md`.
4. http://rti1.localhost:3000 - RTI web-aplikacija podešena kao OAuth2 i OIDC klijent. Početna stranica i RTI i SI aplikacije je login stranica na kojoj se može ulogovati kroz lokalne naloge (koji nisu povezani sa Keycloak instancom) kao i pomoću Keycloak IdP-a. Zbog federacije, prilikom prijave možete koristiti oba Keycloak domena. Nakon prijave, početna stranica prikazuje JWT token. Na dnu stranice možete i uputiti API poziv serveru zaštićenom pomoću OAuth2. Podrazumijevano, API-ju mogu pristupiti samo korisnici koji pripadaju grupi `api-access`. Mapiranje grupe iz SI domena u RTI podešeno je tako da i SI korisnici mogu pristupiti API-ju ako pripadaju grupi `api-access` u SI domenu.
5. http://si1.localhost:4000 - SI web-aplikacija podešena kao SAML klijent. Početna stranica nakon prijave prikazuje informacije o SAML tokenu. Pošto ova web-aplikacija ima i mali backend, frontend prikazuje dva dugmeta za odjavu: lokalna odjava briše samo sesiju te instance, dok SAML odjava šalje `LogoutRequest` Keycloaku i prima `LogoutResponse` na SLS endpointu iste instance.
6. Ako koristite više instanci, instanca `N` dostupna je na portu adresi http://rtiN.localhost:300(N-1) za RTI, odnosno http://siN.localhost:400(N-1) za SI. Npr: http://rti2.localhost:3001, http://si2.localhost:4001

# Ručni režim

1. Izmijenite `.env` fajl: `LAB_MODE=manual`.
2. Zatim možete zasebno podesiti režim svake komponente:
    - `AUTO_POPULATE=true/false` - određuje da li će LDAP baze biti unaprijed popunjene korisnicima iz LDIF fajlova.
    - `KC_LDAP_USERS_MODE=preconfigured/manual` - određuje da li će biti kreirana federacija korisnika između Keycloak-a i LDAP-a. Zahtijeva prethodni korak jer se njime kreira i servisni nalog za Keycloak.
    - `KC_FEDERATION_MODE=preconfigured/manual` - određuje da li postoji federacija između dvije Keycloak instance.

Za povezivanje možete koristiti iste adrese. Ako želite da kreirate LDAP korisnike, morate koristiti konzolu iz kontejnera jer za to ne postoji ugrađeni portal.

Detaljni koraci za ručno podešavanje nalaze se u fajlovima `ManualSetupPortal.sr.md` i `ManualSetupSteps.sr.md`. Prvi opisuje podešavanje kroz grafički interfejs, a drugi podešavanje pomoću skripti.
