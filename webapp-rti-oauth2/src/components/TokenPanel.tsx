import { useState } from "react";
import { decodeJwt } from "../utils/jwt";

interface TokenPanelProps {
  title: string;
  token?: string;
}

export function TokenPanel({ title, token }: TokenPanelProps) {
  const [copied, setCopied] = useState(false);

  if (!token) return null;
  const decoded = decodeJwt(token);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(token);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      setCopied(false);
    }
  };

  return (
    <section className="card token-panel">
      <h3>{title}</h3>
      <textarea className="token-raw" readOnly rows={4} value={token} />
      <div className="token-actions">
        <button onClick={copy}>{copied ? "Copied!" : "Copy token"}</button>
        <a href="https://jwt.io/" target="_blank" rel="noreferrer">
          Open jwt.io (paste to decode)
        </a>
      </div>
      {decoded && (
        <details open>
          <summary>Decoded payload (unverified)</summary>
          <pre className="token-decoded">
            {JSON.stringify(decoded.payload, null, 2)}
          </pre>
        </details>
      )}
    </section>
  );
}
