import type { User } from "oidc-client-ts";

interface IdentitySummaryProps {
  user: User;
}

export function IdentitySummary({ user }: IdentitySummaryProps) {
  const profile = user.profile;
  return (
    <section className="card">
      <h3>Signed-in identity</h3>
      <table className="kv">
        <tbody>
          <tr>
            <th>Username</th>
            <td>{profile.preferred_username ?? "-"}</td>
          </tr>
          <tr>
            <th>Name</th>
            <td>{profile.name ?? "-"}</td>
          </tr>
          <tr>
            <th>Email</th>
            <td>{profile.email ?? "-"}</td>
          </tr>
          <tr>
            <th>Issuer</th>
            <td>{profile.iss}</td>
          </tr>
          <tr>
            <th>Subject</th>
            <td>{profile.sub}</td>
          </tr>
        </tbody>
      </table>
    </section>
  );
}
