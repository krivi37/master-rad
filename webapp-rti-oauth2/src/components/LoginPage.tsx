import { useState, type FormEvent } from "react";
import {
  authenticateLocal,
  setLocalSession,
  type LocalUser,
} from "../localAuth";

interface LoginPageProps {
  instance: number;
  onKeycloakLogin: () => void;
  onLocalLogin: (user: LocalUser) => void;
}

export function LoginPage({
  instance,
  onKeycloakLogin,
  onLocalLogin,
}: LoginPageProps) {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);

  const submitLocal = (event: FormEvent) => {
    event.preventDefault();
    const user = authenticateLocal(username.trim(), password);
    if (!user) {
      setError("Invalid local username or password.");
      return;
    }
    setLocalSession(user);
    onLocalLogin(user);
  };

  return (
    <main className="container">
      <h1>
        Web Application A{" "}
        <span className="instance-chip">Instance {instance}</span>
      </h1>
      <p className="badge">OIDC · Keycloak RTI</p>
      <p className="forbidden">
        403 — You must sign in to view this application.
      </p>

      <div className="login-grid">
        <section className="card">
          <h3>RTI domain</h3>
          <p>
            Single sign-on via Keycloak RTI. Directory and federated users are
            brokered through the identity provider, so one login is shared
            across every app instance and unlocks the protected OAuth2 API.
          </p>
          <button className="primary" onClick={onKeycloakLogin}>
            Log in with RTI domain
          </button>
        </section>

        <section className="card">
          <h3>Local account</h3>
          <p>
            Accounts stored only inside this app, unknown to Keycloak and LDAP.
            No SSO — the session lives in this tab and is gone the moment it is
            cleared, so every other instance asks you to log in again.
          </p>
          <form className="login-form" onSubmit={submitLocal}>
            <label>
              Username
              <input
                autoComplete="username"
                value={username}
                onChange={(event) => setUsername(event.target.value)}
              />
            </label>
            <label>
              Password
              <input
                type="password"
                autoComplete="current-password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
              />
            </label>
            {error && <p className="forbidden">{error}</p>}
            <button type="submit" className="primary">
              Log in locally
            </button>
          </form>
          <p className="hint">Try miroslav-local / local or milica-local / local.</p>
        </section>
      </div>
    </main>
  );
}
