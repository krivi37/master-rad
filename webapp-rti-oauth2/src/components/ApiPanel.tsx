import { useState } from "react";
import { useAuth } from "react-oidc-context";

const apiBaseUrl = import.meta.env.VITE_API_BASE_URL ?? "http://localhost:5000";

type CallState =
  | { status: "idle" }
  | { status: "loading" }
  | { status: "success"; body: unknown }
  | { status: "forbidden"; body: unknown }
  | { status: "unauthorized" }
  | { status: "error"; message: string };

export function ApiPanel() {
  const auth = useAuth();
  const [state, setState] = useState<CallState>({ status: "idle" });

  const callApi = async () => {
    const token = auth.user?.access_token;
    if (!token) {
      setState({ status: "unauthorized" });
      return;
    }

    setState({ status: "loading" });
    try {
      const res = await fetch(`${apiBaseUrl}/api/data`, {
        headers: { Authorization: `Bearer ${token}` },
      });

      if (res.status === 401) {
        setState({ status: "unauthorized" });
        return;
      }

      const body = await res.json().catch(() => null);

      if (res.status === 403) {
        setState({ status: "forbidden", body });
        return;
      }
      if (res.ok) {
        setState({ status: "success", body });
        return;
      }
      setState({
        status: "error",
        message: `Unexpected response (${res.status}).`,
      });
    } catch (err) {
      setState({
        status: "error",
        message: err instanceof Error ? err.message : "Network request failed.",
      });
    }
  };

  return (
    <section className="card api-panel">
      <h3>Protected API</h3>
      <p>
        Calls <code>GET {apiBaseUrl}/api/data</code> with the in-memory access
        token as an <code>Authorization: Bearer</code> header.
      </p>
      <div className="api-actions">
        <button className="primary" onClick={() => void callApi()}>
          Call protected API
        </button>
        {state.status === "loading" && <span>Calling…</span>}
      </div>

      {state.status === "success" && (
        <div className="api-result api-ok">
          <p>
            <strong>200 OK</strong> — the API accepted the access token.
          </p>
          <pre className="token-decoded">
            {JSON.stringify(state.body, null, 2)}
          </pre>
        </div>
      )}

      {state.status === "forbidden" && (
        <div className="api-result api-forbidden">
          <p>
            <strong>403 Forbidden</strong> — the token is valid but this user is
            not in the <code>api-access</code> group.
          </p>
          <pre className="token-decoded">
            {JSON.stringify(state.body, null, 2)}
          </pre>
        </div>
      )}

      {state.status === "unauthorized" && (
        <div className="api-result api-forbidden">
          <p>
            <strong>401 Unauthorized</strong> — the access token is missing or
            expired. Sign in again to obtain a fresh token.
          </p>
          <button onClick={() => void auth.signinRedirect()}>
            Re-authenticate
          </button>
        </div>
      )}

      {state.status === "error" && (
        <div className="api-result api-forbidden">
          <p>
            <strong>Request failed</strong> — {state.message}
          </p>
        </div>
      )}
    </section>
  );
}
