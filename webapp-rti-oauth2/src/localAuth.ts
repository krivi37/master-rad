// Local accounts live ONLY inside this web application. They are unknown to
// Keycloak RTI and to the LDAP directory, so there is no identity-provider
// session behind them and therefore no SSO: the "session" is kept in this
// tab's sessionStorage and vanishes the moment it is cleared, so other app
// instances never see it. This is the deliberate contrast to the brokered
// Keycloak login, which is shared across every instance via the IdP cookie.

export interface LocalUser {
  username: string;
  name: string;
  email: string;
}

interface LocalCredential extends LocalUser {
  password: string;
}

const LOCAL_USERS: LocalCredential[] = [
  {
    username: "miroslav-local",
    password: "local",
    name: "Miroslav Local (RTI app)",
    email: "miroslav@local.rti",
  },
  {
    username: "milica-local",
    password: "local",
    name: "Milica Local (RTI app)",
    email: "milica @local.rti",
  },
];

const STORAGE_KEY = "rti-local-session";

export function authenticateLocal(
  username: string,
  password: string,
): LocalUser | null {
  const match = LOCAL_USERS.find(
    (candidate) =>
      candidate.username === username && candidate.password === password,
  );
  if (!match) return null;
  const { password: _password, ...user } = match;
  return user;
}

export function getLocalSession(): LocalUser | null {
  const raw = sessionStorage.getItem(STORAGE_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as LocalUser;
  } catch {
    return null;
  }
}

export function setLocalSession(user: LocalUser): void {
  sessionStorage.setItem(STORAGE_KEY, JSON.stringify(user));
}

export function clearLocalSession(): void {
  sessionStorage.removeItem(STORAGE_KEY);
}
