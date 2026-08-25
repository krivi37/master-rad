# System requirements:
- Docker Engine, for example Docker Desktop on Windows
- Free host ports: 389, 390, 8081, 8082, 3000, 4000, 5000

# Quickstart (preconfigured mode):

1. Create .env file in root folder
2. Copy contents from .env.example to the .env file
3. Set values:
  a. LAB_MODE=preconfigured
  b. Edit passwords for LDAP_RTI_ADMIN_PASSWORD, LDAP_SI_ADMIN_PASSWORD, KEYCLOAK_ADMIN_PASSWORD and KEYCLOAK_LDAP_BIND_PASSWORD
4. Start Docker Desktop or Docker service
5. From the root folder execute: docker compose up -d --wait api webapp-rti-oauth2 webapp-si-saml-frontend

Now you can connect to various endpoints:
1. http://rti.localhost:8081 - Keycloak instance for RTI realm - use KEYCLOAK admin credentials for logging in
2. http://si.localhost:8082 - Same but for SI realm
3. http://rti.localhost:8081/realms/rti/account and  http://si.localhost:8082/realms/si/account - here you can login using credentials from non-admin users - you can find each user in user-credentials.md
4. http://localhost:3000 - RTI webapp which is set up as an OAuth2 and OIDC client. When logging in you can use both realms due to federation. After logging in,
   the landing page will show the JWT token. Also, at the bottom of the page you can invoke an API call to the server which is protected by OAuth2. By default, the only users
   who can access the api are those who belong to the api-access group. A group mapping is set up from SI realm to RTI to allow SI users to also access the API if they are in the
   SI realm's api-access group
5. http://localhost:4000 - SI webapp which is set up as a SAML client. You can also use both realms to login due to federation. The landing page after login shows SAML token info.
   Since this web app also has a small backend, the frontend exposes 2 Log Out buttons - one for local client log out and the other for destroying the SAML session which invokes
   the API call on the backend app

# Manual mode
1. Edit the env file: LAB_MODE=manual
2. Then each of the component modes can be configured individually:
  a. AUTO_POPULATE=true/false - Controls whether LDAP databases will be prepopulated with users from ldif files
  b. KC_LDAP_USERS_MODE=preconfigured/manual - Controls whether user federation between Keycloak and LDAP will be created. Requires previous step, because it also creates the service account for Keycloak
  c. KC_FEDERATION_MODE=preconfigured/manual - Controls whether federation exists between the two Keycloak instances

  You can use the same endpoints to connect. If you want to create LDAP users, console needs to be used from the container since no built in portal exists for this.

Detailed manual setup steps in Serbian are in ManualSetupPortal.sr.md and ManualSetupSteps.sr.md. First one is for GUI experience, the second one is the setup using scripts.
