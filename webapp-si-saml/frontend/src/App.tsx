import { useCallback, useEffect, useState } from "react";
import { IdentitySummary } from "./components/IdentitySummary";
import { AssertionPanel } from "./components/AssertionPanel";
import { SessionTimer } from "./components/SessionTimer";
import { LoginPage } from "./components/LoginPage";
import type { SamlSession } from "./types";

type Status = "loading" | "anonymous" | "authenticated";

// Which copy this is (base app = 1). Copies get a distinct accent theme so they
// are visually distinguishable when demonstrating SSO.
const instance = Number(import.meta.env.VITE_APP_INSTANCE ?? 1) || 1;
document.documentElement.dataset.theme = String((instance - 1) % 3);

const go = (path: string) => () => {
  window.location.href = path;
};

export default function App() {
  const [status, setStatus] = useState<Status>("loading");
  const [session, setSession] = useState<SamlSession | null>(null);

  const loadSession = useCallback(async () => {
    try {
      const response = await fetch("/api/session", {
        credentials: "same-origin",
      });
      if (!response.ok) throw new Error("Not authenticated");
      setSession((await response.json()) as SamlSession);
      setStatus("authenticated");
    } catch {
      setStatus("anonymous");
    }
  }, []);

  useEffect(() => {
    void loadSession();
  }, [loadSession]);

  if (status === "loading") {
    return (
      <main className="container">
        <p>Loading…</p>
      </main>
    );
  }

  if (status === "anonymous" || !session) {
    return <LoginPage instance={instance} onLocalSuccess={loadSession} />;
  }

  const isLocal = session.authType === "local";

  return (
    <main className="container">
      <header className="topbar">
        <div>
          <h1>Welcome, {session.subject}</h1>
          <p className="badge">
            {isLocal ? "Local account · no SSO" : "SAML · Keycloak SI"}{" "}
            <span className="instance-chip">Instance {instance}</span>
          </p>
        </div>
        <div className="logout-actions">
          {isLocal ? (
            <button className="primary" onClick={go("/saml/local-logout")}>
              Log out
            </button>
          ) : (
            <>
              <button className="primary" onClick={go("/saml/logout")}>
                SAML logout (SLO)
              </button>
              <button onClick={go("/saml/local-logout")}>
                Local logout (keep SSO)
              </button>
            </>
          )}
        </div>
      </header>

      <IdentitySummary identity={session} />

      {isLocal ? (
        <section className="card">
          <h3>No single sign-on</h3>
          <p>
            This account is not known to Keycloak, so there is no SAML assertion
            and no identity-provider session. The login is only the{" "}
            <code>webapp_b_sid</code> cookie: delete it and you are logged out
            immediately, and every other app instance asks you to sign in again.
            A directory user, by contrast, stays signed in across instances
            until the shared SSO session ends.
          </p>
        </section>
      ) : (
        <>
          <SessionTimer expiresAt={session.sessionNotOnOrAfter} />
          {session.assertionXml && <AssertionPanel xml={session.assertionXml} />}
        </>
      )}
    </main>
  );
}
