# GEO-Websuche: Einrichtung der Vorlagen openai-websuche und gemini-websuche

Stufe 1 „Sicher verbinden“: zwei REST-Vorlagen 1.0.1, je ein lesender JSON-POST `ask`. Live belegt am
03.11.2026 (13 Fragen des Skripts, alle ok).

## Was die Vorlage hält und was nicht

- **Die Frage ist frei.** `frage` ist ein String ohne `enum`. Die Vorlage erzwingt keine feste Frage; „fest“ ist
  allein das aufrufende Skript. Die Grenze ist das Recht auf die Integration. Weil `ask` ein lesender POST ist,
  genügt dafür ein Recht auf die ganze Integration.
- **Nur das Skript-Token der GEO-Messung hält das Recht** (Aktivierungsregel wie bei
  `linkedin-seite-community`). Die Token-ID steht im Probelauf-Vermerk. Kein Team-Token, kein
  SSO-Nutzer, kein weiteres Token bekommt `openai-websuche` oder `gemini-websuche`.
- **Schwärzung nur im Audit und nur auf der Tiefe „Metadaten“.** `redact_params: [frage]` zeigt die Frage im
  Audit als `[REDACTED]`, solange die Protokolltiefe „Metadaten“ gilt (Default). Auf „Abfragen“ oder
  „Antworten“ steht die volle Frage im Inhaltsspeicher des Audit-Logs
  ([Audit & Redaction](connector-spec.md#audit--redaction-redact_params)). Beim Anbieter ist sie nie geschwärzt.
- **Kein Kostendeckel im Gateway.** Ein `daily_cap` an einem Lesewerkzeug ist ein Ladefehler, die Websuche ist
  kostenpflichtig. Den Anbieterdeckel setzt der Betreiber beim Anbieter, das Skript begrenzt die Läufe.

## Pflichtschritt vor dem ersten Aufruf: Rückwandlung abschalten

Ein Pseudonym in der Frage wird vor dem Aufruf in Klartext zurückgewandelt, auch wenn es in einer anderen
Integration entstanden ist (Produkt-Doku, nicht öffentlich, Abschnitt „Rückwandlung abschalten“). Ohne den
folgenden Schritt gehen Klarnamen aus Pseudonymen an Google bzw. OpenAI.

Der Schalter (`RehydrateOff`) ist eine Betreiber-Einstellung je Integration und Werkzeug. Er ist bewusst
nicht aus der Spec setzbar und steht deshalb nicht in der Vorlage. Der Betreiber stellt ihn für `ask` auf
**Aus**, über einen von drei Wegen:

- Admin-GUI: Integration öffnen, Sektion „Pseudonymisierung“, Rückwandlung für `ask` auf *Aus*.
- REST: `PUT /integrations/{name}/privacy/ask` mit `"rehydrate": false`.
- Admin-MCP: `admin_set_tool_privacy` mit `integration`, `tool: ask` und `rehydrate: off`.

Danach bekommt der Anbieter das Pseudonym (`‹name-…›`) statt des Klartexts. Die Änderung wirkt sofort.

## Einrichtung

1. Vault-Credential `openai-geo` bzw. `gemini-geo` (API-Schlüssel) ablegen. Der Schlüssel steht nie in der Spec.
2. Integration aus der Vorlage anlegen und die Rückwandlung für `ask` abschalten (siehe oben).
3. Das Recht auf die Integration an das Skript-Token der GEO-Messung vergeben, an kein weiteres.
4. Beim Anbieter einen Ausgabendeckel setzen.
