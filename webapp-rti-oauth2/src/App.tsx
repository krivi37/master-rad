import { useAuth } from "react-oidc-context";
import { IdentitySummary } from "./components/IdentitySummary";
import { TokenPanel } from "./components/TokenPanel";
import { ApiPanel } from "./components/ApiPanel";

export default function App() {
  const auth = useAuth();

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
      <main className="container">
        <h1>Web Application A</h1>
        <p className="badge">OIDC · Keycloak RTI</p>
        <p className="forbidden">
          403 — You must sign in to view this application.
        </p>
        <button className="primary" onClick={() => void auth.signinRedirect()}>
          Log in with Keycloak (RTI)
        </button>
      </main>
    );
  }

  const user = auth.user;

  return (
    <main className="container">
      <header className="topbar">
        <div>
          <h1>Welcome, {user.profile.preferred_username ?? "user"}</h1>
          <p className="badge">OIDC · Keycloak RTI</p>
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
