import { useState } from "react";
import { useAuth } from "react-oidc-context";
import { IdentitySummary } from "./components/IdentitySummary";
import { TokenPanel } from "./components/TokenPanel";
import { ApiPanel } from "./components/ApiPanel";
import { LoginPage } from "./components/LoginPage";
import { LocalIdentityView } from "./components/LocalIdentityView";
import {
  clearLocalSession,
  getLocalSession,
  type LocalUser,
} from "./localAuth";

// Which copy this is (base app = 1). Copies get a distinct accent theme so they
// are visually distinguishable when demonstrating SSO.
const instance = Number(import.meta.env.VITE_APP_INSTANCE ?? 1) || 1;
document.documentElement.dataset.theme = String((instance - 1) % 3);

export default function App() {
  const auth = useAuth();
  const [localUser, setLocalUser] = useState<LocalUser | null>(() =>
    getLocalSession(),
  );

  // A local account has no IdP session, so it takes precedence over the OIDC
  // state machine: we short-circuit before any Keycloak loading/redirect.
  if (localUser && !auth.isAuthenticated) {
    return (
      <LocalIdentityView
        user={localUser}
        instance={instance}
        onLogout={() => {
          clearLocalSession();
          setLocalUser(null);
        }}
      />
    );
  }

  if (auth.isLoading) {
    return (
      <main className="container">
        <p>Loading…</p>
      </main>
    );
  }

  if (auth.error) {
    return (
      <main className="container">
        <h1>Authentication error</h1>
        <p className="forbidden">{auth.error.message}</p>
        <button className="primary" onClick={() => void auth.signinRedirect()}>
          Try again
        </button>
      </main>
    );
  }

  if (!auth.isAuthenticated || !auth.user) {
    return (
      <LoginPage
        instance={instance}
        onKeycloakLogin={() => void auth.signinRedirect()}
        onLocalLogin={setLocalUser}
      />
    );
  }

  const user = auth.user;

  return (
    <main className="container">
      <header className="topbar">
        <div>
          <h1>Welcome, {user.profile.preferred_username ?? "user"}</h1>
          <p className="badge">
            OIDC · Keycloak RTI{" "}
            <span className="instance-chip">Instance {instance}</span>
          </p>
        </div>
        <button onClick={() => void auth.signoutRedirect()}>Log out</button>
      </header>

      <IdentitySummary user={user} />

      <div className="tokens">
        <TokenPanel title="ID token" token={user.id_token} />
        <TokenPanel title="Access token" token={user.access_token} />
      </div>

      <ApiPanel />
    </main>
  );
}
