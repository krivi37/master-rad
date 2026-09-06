import type { LocalUser } from "../localAuth";

interface LocalIdentityViewProps {
  user: LocalUser;
  instance: number;
  onLogout: () => void;
}

export function LocalIdentityView({
  user,
  instance,
  onLogout,
}: LocalIdentityViewProps) {
  return (
    <main className="container">
      <header className="topbar">
        <div>
          <h1>Welcome, {user.username}</h1>
          <p className="badge">
            Local account · no SSO{" "}
            <span className="instance-chip">Instance {instance}</span>
          </p>
        </div>
        <button onClick={onLogout}>Log out</button>
      </header>

      <section className="card">
        <h3>Signed-in identity</h3>
        <table className="kv">
          <tbody>
            <tr>
              <th>Username</th>
              <td>{user.username}</td>
            </tr>
            <tr>
              <th>Name</th>
              <td>{user.name}</td>
            </tr>
            <tr>
              <th>Email</th>
              <td>{user.email}</td>
            </tr>
            <tr>
              <th>Issuer</th>
              <td>local-accounts (webapp-rti-oauth2)</td>
            </tr>
          </tbody>
        </table>
      </section>

      <section className="card">
        <h3>No single sign-on</h3>
        <p>
          This account is not known to Keycloak, so there is no OAuth2 token and
          no identity-provider session. The login is held only in this tab's{" "}
          <code>sessionStorage</code>; clearing it or opening another instance
          forces a fresh login. A real IdP user, by contrast, stays signed in
          across every instance until the shared SSO session ends.
        </p>
      </section>

      <section className="card api-panel">
        <h3>Protected API</h3>
        <div className="api-result api-forbidden">
          <p>
            <strong>Unavailable</strong> — local accounts never receive an
            OAuth2 access token, so <code>GET /api/data</code> cannot be called.
            Sign in with the RTI domain to obtain a bearer token.
          </p>
        </div>
      </section>
    </main>
  );
}
