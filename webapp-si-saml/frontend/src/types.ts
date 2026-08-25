export type SamlAttributes = Record<string, string | string[]>;

export interface SamlSession {
  subject: string;
  issuer: string;
  nameIDFormat?: string;
  sessionIndex?: string;
  sessionNotOnOrAfter?: string;
  attributes: SamlAttributes;
  assertionXml: string;
}
