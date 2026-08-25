import { useEffect, useState } from "react";
import { IdentitySummary } from "./components/IdentitySummary";
import { AssertionPanel } from "./components/AssertionPanel";
import { SessionTimer } from "./components/SessionTimer";
import type { SamlSession } from "./types";

type Status = "loading" | "anonymous" | "authenticated";

const go = (path: string) => () => {
  window.location.href = path;
};

export default function App() {
  const [status, setStatus] = useState<Status>("loading");
  const [session, setSession] = useState<SamlSession | null>(null);

  useEffect(() => {
    void fetch("/api/session", { credentials: "same-origin" })
      .then(async (response) => {
        if (!response.ok) throw new Error("Not authenticated");
        setSession((await response.json()) as SamlSession);
        setStatus("authenticated");
      })
      .catch(() => setStatus("anonymous"));
  }, []);

  if (status === "loading") {
    return (
      <main className="container">
        <p>Loading…</p>
      </main>
    );
  }

  if (status === "anonymous" || !session) {
    return (
      <main className="container">
        <h1>Web Application B</h1>
        <p className="badge">SAML · Keycloak SI</p>
        <p className="forbidden">
          403 — You must sign in to view this application.
        </p>
        <button className="primary" onClick={go("/saml/login")}>
          Log in with Keycloak (SI)
        </button>
      </main>
    );
  }

  return (
    <main className="container">
      <header className="topbar">
        <div>
          <h1>Welcome, {session.subject}</h1>
          <p className="badge">SAML · Keycloak SI</p>
        </div>
        <div className="logout-actions">
          <button className="primary" onClick={go("/saml/logout")}>
            SAML logout (SLO)
          </button>
          <button onClick={go("/saml/local-logout")}>
            Local logout (keep SSO)
          </button>
        </div>
      </header>

      <IdentitySummary identity={session} />

      <SessionTimer expiresAt={session.sessionNotOnOrAfter} />

      {session.assertionXml && <AssertionPanel xml={session.assertionXml} />}
    </main>
  );
}
