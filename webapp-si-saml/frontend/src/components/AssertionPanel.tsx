import { useState } from "react";

interface AssertionPanelProps {
  xml: string;
}

// Indent the single-line SAML response so it is readable in the teaching panel.
// React escapes the string when it renders inside <pre>, so the XML is shown
// as inert text rather than being parsed as markup.
function formatXml(xml: string): string {
  const padding = "  ";
  const withBreaks = xml.replace(/(>)(<)(\/*)/g, "$1\n$2$3");
  let depth = 0;
  return withBreaks
    .split("\n")
    .map((node) => {
      let indent = 0;
      if (/.+<\/\w[^>]*>$/.test(node)) {
        indent = 0;
      } else if (/^<\/\w/.test(node) && depth > 0) {
        depth -= 1;
      } else if (/^<\w[^>]*[^/]>.*$/.test(node)) {
        indent = 1;
      }
      const line = padding.repeat(depth) + node;
      depth += indent;
      return line;
    })
    .join("\n");
}

export function AssertionPanel({ xml }: AssertionPanelProps) {
  const [copied, setCopied] = useState(false);
  const pretty = formatXml(xml);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(xml);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      setCopied(false);
    }
  };

  return (
    <section className="card">
      <h3>Validated SAML response</h3>
      <p>
        This XML was signature-checked, audience-checked, and time-checked by the
        Express service provider before the session was created.
      </p>
      <div className="token-actions" style={{ marginBottom: "0.5rem" }}>
        <button onClick={copy}>{copied ? "Copied!" : "Copy XML"}</button>
      </div>
      <pre className="assertion-xml">{pretty}</pre>
    </section>
  );
}
