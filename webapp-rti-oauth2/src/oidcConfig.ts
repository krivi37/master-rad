import { InMemoryWebStorage, WebStorageStateStore } from "oidc-client-ts";
import type { AuthProviderProps } from "react-oidc-context";

const authority =
  import.meta.env.VITE_OIDC_AUTHORITY ?? "http://rti.localhost:8081/realms/rti";
const clientId = import.meta.env.VITE_OIDC_CLIENT_ID ?? "webapp-rti-oauth2";
const redirectUri =
  import.meta.env.VITE_OIDC_REDIRECT_URI ?? "http://localhost:3000";

export const oidcConfig: AuthProviderProps = {
  authority,
  client_id: clientId,
  redirect_uri: redirectUri,
  post_logout_redirect_uri: redirectUri,
  response_type: "code",
  scope: "openid profile email",
  // Refresh the access token in the background so API calls keep working after
  // the short access-token lifetime without forcing a full redirect.
  automaticSilentRenew: true,
  // Public client + PKCE: access/ID tokens live only in memory; the login/PKCE
  // state uses sessionStorage so it survives the redirect round-trip.
  userStore: new WebStorageStateStore({ store: new InMemoryWebStorage() }),
  stateStore: new WebStorageStateStore({ store: window.sessionStorage }),
  onSigninCallback: () => {
    window.history.replaceState({}, document.title, window.location.pathname);
  },
};
