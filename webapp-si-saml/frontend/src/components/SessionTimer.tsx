import { useEffect, useState } from "react";

interface SessionTimerProps {
  // ISO 8601 timestamp of the IdP SSO session expiry (SessionNotOnOrAfter).
  expiresAt?: string;
}

function formatRemaining(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const pad = (n: number) => String(n).padStart(2, "0");
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`;
}

export function SessionTimer({ expiresAt }: SessionTimerProps) {
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, []);

  if (!expiresAt) return null;

  const expiryMs = new Date(expiresAt).getTime();
  const remaining = expiryMs - now;
  const expired = remaining <= 0;

  return (
    <section className="card">
      <h3>Keycloak SSO session</h3>
      <table className="kv">
        <tbody>
          <tr>
            <th>Expires at</th>
            <td>{new Date(expiresAt).toLocaleString()}</td>
          </tr>
          <tr>
            <th>Time left</th>
            <td className={expired ? "forbidden" : undefined}>
              {expired ? "expired" : formatRemaining(remaining)}
            </td>
          </tr>
        </tbody>
      </table>
      <p>
        While this SSO session is alive, a <strong>local logout</strong> is
        reversed instantly on the next login (no password prompt). A full{" "}
        <strong>SAML logout</strong> ends it at the identity provider.
      </p>
    </section>
  );
}
