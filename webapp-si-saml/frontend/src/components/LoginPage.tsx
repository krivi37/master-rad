import { useState, type FormEvent } from "react";

interface LoginPageProps {
  instance: number;
  onLocalSuccess: () => void | Promise<void>;
}

export function LoginPage({ instance, onLocalSuccess }: LoginPageProps) {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const submitLocal = async (event: FormEvent) => {
    event.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      const response = await fetch("/local/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "same-origin",
        body: JSON.stringify({ username: username.trim(), password }),
      });
      if (!response.ok) {
        setError("Invalid local username or password.");
        setSubmitting(false);
        return;
      }
      await onLocalSuccess();
    } catch {
      setError("Login request failed.");
      setSubmitting(false);
    }
  };

  return (
    <main className="container">
      <h1>
        Web Application B{" "}
        <span className="instance-chip">Instance {instance}</span>
      </h1>
      <p className="badge">SAML · Keycloak SI</p>
      <p className="forbidden">
        403 — You must sign in to view this application.
      </p>

      <div className="login-grid">
        <section className="card">
          <h3>SI domain</h3>
          <p>
            Single sign-on via Keycloak SI. Directory and federated users share
            one identity-provider session, so a login here is reused across
            every app instance without re-entering credentials.
          </p>
          <button
            className="primary"
            onClick={() => {
              window.location.href = "/saml/login";
            }}
          >
            Log in with SI domain
          </button>
        </section>

        <section className="card">
          <h3>Local account</h3>
          <p>
            Accounts stored only inside this app, unknown to Keycloak and LDAP.
            No SSO — the session cookie is the whole login, so deleting it logs
            you out and every other instance asks you to sign in again.
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
            <button type="submit" className="primary" disabled={submitting}>
              {submitting ? "Signing in…" : "Log in locally"}
            </button>
          </form>
          <p className="hint">Try sonja-local / local or ljubo-local / local.</p>
        </section>
      </div>
    </main>
  );
}
