import type { SamlAttributes, SamlSession } from "../types";

interface IdentitySummaryProps {
  identity: SamlSession;
}

function attributeValue(value: string | string[]): string {
  return Array.isArray(value) ? value.join(", ") : value;
}

export function IdentitySummary({ identity }: IdentitySummaryProps) {
  const attributes: SamlAttributes = identity.attributes ?? {};
  return (
    <section className="card">
      <h3>Signed-in identity (SAML)</h3>
      <table className="kv">
        <tbody>
          <tr>
            <th>Subject (NameID)</th>
            <td>{identity.subject}</td>
          </tr>
          <tr>
            <th>Issuer</th>
            <td>{identity.issuer}</td>
          </tr>
          {identity.nameIDFormat && (
            <tr>
              <th>NameID format</th>
              <td>{identity.nameIDFormat}</td>
            </tr>
          )}
          {Object.entries(attributes).map(([name, value]) => (
            <tr key={name}>
              <th>{name}</th>
              <td>{attributeValue(value)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}
