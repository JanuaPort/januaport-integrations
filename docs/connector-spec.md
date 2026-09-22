# Connector-Spec — Format-Referenz

Ein Connector ist eine YAML-Datei, die aus einer REST-API berechtigte
MCP-Tools macht. JanuaPort lädt beim Start alle `*.yaml`/`*.yml` aus dem
Connector-Verzeichnis (`JNPT_CONNECTORS_DIR`, Default `/data/connectors`),
prüft sie und bietet ihre Tools über den MCP-Endpoint an. Diese Seite ist die
Referenz zum Selber-Schreiben — keine Programmierkenntnisse nötig.

> **Zur Laufzeit anlegen (ohne Neustart, Story #63):** Neben den Dateien kann
> ein Connector auch **zur Laufzeit** persistiert werden:
> `cat connector.yaml | jnpt connector add` (alternativ `--file <pfad>`)
> validiert die Spec und legt sie in der Datenbank ab (eine zweite Quelle neben
> dem Verzeichnis; Datei-Connectoren bleiben unverändert unterstützt). Ein
> **laufender** Server übernimmt sie ohne Container-Neustart per Reload-Signal:
> `docker compose kill -s HUP jnpt` (bzw. `kill -HUP <pid>` lokal). Bei einer
> Namens-Kollision zwischen Datei und DB bricht das Laden mit einer klaren
> Meldung ab. Es gibt bewusst keine Versionierung/Historie (nur der aktuelle
> Stand) und keinen automatischen Datei-Watch — der Reload ist explizit.

> **Standard read-only:** `GET`-Aufrufe sind der Normalfall. Seit Phase 2 gibt
> es zusätzlich schreibende Tools — `POST`, markiert mit `write: true`, in genau
> zwei Body-Formen: **Datei-Upload** (`encoding: multipart`) und **JSON-Body**
> (`encoding: json`). Siehe [Schreibende Tools](#schreibende-tools-write) und
> [JSON-Body](#json-body-encoding-json). Alles andere (PUT/PATCH/DELETE, mehrere
> Dateien) bleibt dem externen MCP-Server vorbehalten.

## Vollständiges Beispiel

```yaml
name: demo-erp                      # eindeutiger Connector-Name (Prefix der Tool-Namen)
version: "1.0.0"                    # Pflicht: Fassung dieser Spec (SemVer MAJOR.MINOR.PATCH)
base_url: https://erp.example.com   # Basis-URL der API (http/https)

auth:
  header: Authorization             # Name des HTTP-Headers
  template: "Bearer {{credential}}" # Header-Wert; {{credential}} = das Secret
  credential: demo-erp-api-key      # Name des Secrets im Vault (siehe unten)

timeout: 30s                        # optional: Zeitlimit pro Aufruf (Default 30s, max 120s)
min_interval: 200ms                 # optional: Mindestabstand zwischen zwei Aufrufen
redact_params: [status]             # optional: diese Parameter erscheinen im Audit-Log als [REDACTED]

tools:
  - name: list_invoices
    description: >
      Lists invoices within a date range. Returns invoice number, date,
      contact name and gross total. Dates are ISO 8601 (YYYY-MM-DD). Use the
      page parameter (0-based) to page through large result sets.
    check: true                     # optional: dieses Tool nutzt `jnpt connector check` als Probe
    params:
      - name: from
        description: Start date (inclusive), format YYYY-MM-DD.
        type: string
        required: true
      - name: status
        description: Optional status filter.
        type: string
        enum: [open, paid, overdue]
      - name: page
        description: Page number, 0-based. Defaults to the first page.
        type: integer
    request:
      method: GET
      path: /v1/invoices            # relativ zur base_url; {param} = Platzhalter
      query:
        - name: from
          value: "{from}"
        - name: status
          value: "{status}"         # weggelassen, wenn der Parameter nicht gesetzt ist
        - name: page
          value: "{page}"
    response: content               # optional: JMESPath-Ausdruck auf die Antwort

  - name: get_invoice
    description: Returns a single invoice with all line items, by its id.
    params:
      - name: id
        description: The invoice id (from list_invoices).
        type: string
        required: true
    request:
      method: GET
      path: /v1/invoices/{id}       # Pfad-Platzhalter
```

## Felder im Detail

### Oberste Ebene

| Feld | Pflicht | Bedeutung |
|---|---|---|
| `name` | ja | Eindeutiger Connector-Name. Wird zum **Prefix** jedes Tool-Namens (`demo_erp_list_invoices`). Bindestriche werden zu Unterstrichen. ⚠️ **Seit Bug #596:** Ein Name, der nach dieser Normalisierung kein gültiges Präfix ergibt (Großbuchstaben, Umlaute, Punkt, Leerzeichen, führende Ziffer), wird bei der **Anlage über die Admin-Fläche abgelehnt**; ein solcher Name im **Bestand** hält den Start NICHT auf, erzeugt aber beim Start eine **WARN-Zeile** mit Namen und Grund. Umbenannt wird nichts automatisch — ein Rename berührt Scopes, Tokens und Team-Zuordnungen. **Reserviert** (das Gateway belegt diese Namen selbst — eine Integration dieses Namens verhindert den Start): `memory`, `kartei`, `usecase` (#642), `wissen` (#647), `ablage` (#726), `ping`, `catalog`, `report_problem`. |
| `version` | **ja** | Fassung dieser Spec als **SemVer** `MAJOR.MINOR.PATCH`, in Anführungszeichen (`"1.0.0"`). Kein führendes `v`, kein `-beta`, kein `+build`, keine führenden Nullen. Fehlt sie oder ist sie ungültig, lädt die Spec **nicht** (siehe [Warum `version` Pflicht ist](#warum-version-pflicht-ist)). |
| `base_url` | ja | Basis-URL der API (`http://` oder `https://` mit Host). |
| `auth` | ja | Wie das Credential in jeden Request kommt (siehe unten). |
| `headers` | nein | **Statische Request-Header** für jeden Aufruf dieses Connectors (siehe [Statische Request-Header](#statische-request-header-headers)). Nur feste Werte. |
| `timeout` | nein | Zeitlimit pro Aufruf, z. B. `30s`, `1500ms`. Default 30s, Obergrenze 120s. |
| `min_interval` | nein | Mindestabstand zwischen zwei Aufrufen dieses Connectors (z. B. `500ms` bei ~2 Anfragen/Sekunde). Verhindert, dass das Zielsystem drosselt. |
| `redact_params` | nein | Liste von Parameter-Namen, deren Werte im **Audit-Log** als `[REDACTED]` erscheinen (siehe unten). |
| `endpoint_view` | nein | `true` macht diesen Connector zu einem eigenen **benannten MCP-Endpoint** `/mcp/v/<name>` (#164) — der Client sieht dann NUR die Tools dieses Connectors als eigene „Integration" (kleinere Tool-Liste). Reine Sicht: die effektiven Tools bleiben `Scope ∩ View`; Auth/Berechtigung sind identisch zu `/mcp`. Default `false`. **Seit #216 ist das der ANLAGE-Default:** der Schalter lässt sich nachträglich in der Admin-GUI bzw. über `PUT /api/admin/integrations/{name}/endpoint-view` umstellen (wirkt ohne Neustart und überstimmt diesen Wert in beide Richtungen). |
| `base_name` | nein | Name der Katalog-Vorlage, aus der diese Spec zuletzt per `jnpt connector upgrade` fortgeschrieben wurde (Story #709) — **nur bei einer DATEI-Integration** relevant, die Datei-Entsprechung der DB-Provenienz-Spalte gleichen Namens (siehe `connector-catalog-delivery.md` (Produkt-Doku, nicht öffentlich)). Rein informativ: Kein Verhalten der Runtime hängt daran, nur der nächste `connector upgrade`-Lauf nutzt es, um die Vorlage ohne erneutes `--vorlage` wiederzufinden. Wird nie von Hand gesetzt. |
| `tools` | ja | Liste der angebotenen Tools (mindestens eins). |

### Warum `version` Pflicht ist

Eine Spec ohne Fassung lässt sich nicht **ausliefern**. Genau das ist seit
Epic #424 die Aufgabe der Connector-Bibliothek: Die mitgelieferten Vorlagen
stehen als **Katalog** im Image (siehe
„Katalog & Anhebung“ (Produkt-Doku, nicht öffentlich)), eine Integration merkt
sich, **auf welcher Fassung sie basiert**, und ein Update — per neuem Image
oder später per signiertem Bundle (#123) — muss beantworten können: *ist das
neuer als das, worauf die laufende Instanz beruht, und was ändert sich dabei?*

Die Antwort hängt an zwei Konventionen, die `version` erst möglich macht:

- **PATCH/MINOR** (`1.0.0` → `1.0.1`, `1.1.0`) = ein **Fix ohne Änderung der
  Werkzeug-Fläche**: bessere Beschreibungen, ein korrigiertes
  `response`-Mapping, ein zusätzlicher statischer Header, ein anderes `timeout`.
- **MAJOR** (`1.x.y` → `2.0.0`) = die **Werkzeug-Fläche ändert sich**: ein Tool
  kommt hinzu/fällt weg/wird umbenannt, ein Parameter oder sein Typ ändert sich,
  ein Tool wird schreibend, eine Privacy-Deklaration wird kleiner, `base_url`
  oder `auth` zeigen woandershin.

Damit das eine **Mechanik** und nicht nur eine Bitte ist, prüft der
**Flächen-Wächter** bei jeder Anhebung die Aussage gegen die Wirklichkeit: Eine
`PATCH`/`MINOR`-Erhöhung, die die Fläche verändert, wird **fail-closed
abgewiesen** (siehe „Katalog & Anhebung“ (Produkt-Doku, nicht öffentlich)).

**Formregeln.** Genau drei nicht-negative Ganzzahlen, durch Punkte getrennt.
Kein führendes `v` (`v1.0.0` ✗), kein Prerelease (`1.0.0-beta` ✗), kein
Build-Suffix (`1.0.0+7` ✗), keine führenden Nullen (`01.0.0` ✗), keine
Zweierform (`1.0` ✗). Die Enge ist Absicht: Die Version wird **persistiert**
(als `base_version` einer Integration) und trägt eine fail-closed-Entscheidung —
zwei Schreibweisen derselben Version wären zwei Werte, die sich nicht mehr
sicher vergleichen ließen. **Immer in Anführungszeichen**, sonst liest YAML
`version: 1.0` als Zahl.

> **⚠️ Beim Update aus einer Version vor #424:** Bestehende Specs **ohne**
> `version:` laden nach dem Update **nicht mehr** — weder aus dem Verzeichnis
> noch aus der Datenbank; der Server startet dann mit einem klaren Fehler nicht.
> Das ist eine bewusste Entscheidung (keine Bestands-Ausnahme, PO-Entscheid
> 13.08.2026): eine „versionslose" Sonderklasse wäre für immer von Katalog,
> Anhebung und Bundle ausgeschlossen gewesen. **Die Reparatur ist eine Zeile
> YAML** — siehe „Update-Runbook §1a“ (Produkt-Doku, nicht öffentlich).

### `auth`

| Feld | Pflicht | Bedeutung |
|---|---|---|
| `header` | ja | Name des HTTP-Headers, meist `Authorization`. |
| `template` | ja | Wert des Headers mit dem Platzhalter `{{credential}}`, z. B. `"Bearer {{credential}}"` oder `"{{credential}}"`. |
| `credential` | ja | **Name** des Secrets im Vault — nie das Secret selbst. Anlegen mit `jnpt credential set --name <name>` (siehe README). |
| `type` | nein | Herkunft des Werts, der `{{credential}}` füllt. Weglassen = statisches Vault-Credential (Default, unverändertes Verhalten). `oauth2_client_credentials` = JanuaPort holt sich einen Access-Token selbst (siehe [App-only-Token](#app-only-token-authtype-oauth2_client_credentials)). |

Das Secret steht **niemals** in der Spec: Die Datei darf bedenkenlos eingecheckt
werden. JanuaPort setzt das Secret erst beim Aufruf in den Header ein und schreibt es
in kein Log und keine Fehlermeldung.

## App-only-Token (`auth.type: oauth2_client_credentials`)

Moderne B2B-APIs (Microsoft Graph, viele SaaS-Anbieter) akzeptieren keinen
statischen API-Key mehr, sondern verlangen einen **kurzlebigen Access-Token**.
Für unbeaufsichtigte Prozesse gibt es dafür den **Client-Credentials-Grant**:
die Anwendung weist sich selbst aus, ohne dass ein Mensch etwas bestätigt.

Setzt eine Spec `auth.type: oauth2_client_credentials`, holt JanuaPort den Token
**selbst** beim Token-Endpoint, hält ihn im Speicher und erneuert ihn rechtzeitig
vor Ablauf. Für den Rest der Spec ändert sich **nichts** — der Token wird über
dasselbe `template` in denselben `header` gesetzt wie ein statisches Credential.

```yaml
auth:
  type: oauth2_client_credentials
  header: Authorization
  template: "Bearer {{credential}}"
  credential: graph-pilot            # Vault-Name des CLIENT SECRET
  token_url: https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token
  client_id: "<client-id>"           # kein Secret — gehört in die Spec
  scopes: ["https://graph.microsoft.com/.default"]
```

| Feld | Pflicht | Bedeutung |
|---|---|---|
| `type` | nein | `oauth2_client_credentials`. Weglassen = statisches Vault-Credential (Default). Ein anderer Wert ist ein Ladefehler. |
| `token_url` | ja (bei diesem `type`) | Der OAuth2-Token-Endpoint. **Muss `https://` sein** (über diese Verbindung geht das Client-Secret) und darf **keine Zugangsdaten in der URL** tragen. |
| `client_id` | ja (bei diesem `type`) | Client-/Anwendungs-ID der App-Registrierung. Kein Secret. |
| `scopes` | ja (bei diesem `type`) | Liste der angeforderten Scopes, mindestens einer. Bei Microsoft Graph app-only ist das `https://graph.microsoft.com/.default`. |
| `credential` | ja | Bleibt Pflicht und benennt jetzt das **Client-Secret** im Vault (`jnpt credential set --name graph-pilot`). |

**Einrichten in drei Schritten:**

```bash
# 1. Client-Secret in den Vault (write-only, erscheint nie wieder)
printf '%s' '<client-secret>' | jnpt credential set --name graph-pilot

# 2. Spec ablegen (Datei im Connector-Verzeichnis oder `jnpt connector add`) —
#    token_url/client_id durch die Werte der eigenen App-Registrierung ersetzen,
#    eine aus dem Katalog übernommene Vorlage trägt hier noch die Null-GUID
#    00000000-0000-0000-0000-000000000000 als Platzhalter.
# 3. Prüfen — Stufe 4 holt einen echten Token und ruft die echte API auf
jnpt connector check <connector-name>
```

> **Der Platzhalter läuft nicht an (Story #709, fail-closed).** Bleibt
> `token_url` oder `client_id` bei der Null-GUID, lehnt sowohl die
> **Aktivierung** (`jnpt connector add`/`activate`, die Admin-API, eine
> DB-Anhebung) als auch `jnpt connector check` (dessen Stufe 2) klar ab — mit
> dem betroffenen Feld in der Meldung, statt erst beim ersten Aufruf mit einem
> Token-Endpoint-Fehler zu scheitern, der auf das (intakte) `credential` zeigt.
> Details und die Begründung, warum die Prüfung NICHT am Start/Ladeweg sitzt,
> stehen in `connector-catalog-delivery.md` (Produkt-Doku, nicht öffentlich).

**Was JanuaPort dabei zusichert:**

- **Das Client-Secret liegt nur im Vault** und wird nur für den Token-Request
  verwendet. Der **Access-Token lebt ausschließlich im Speicher** — er wird nie
  gespeichert, nie geloggt, erscheint in keiner Fehlermeldung und in keiner
  API-Antwort. Spiegelt das Zielsystem ihn in einen Fehler-Body zurück, wird er
  redigiert wie jedes andere Credential.
- **Erneuerung vor Ablauf:** JanuaPort holt den nächsten Token ~60 Sekunden vor dem
  Ende der vom Anbieter genannten Gültigkeit, nicht erst nach einem 401.
- **Ein Token-Request, auch bei vielen parallelen Aufrufen** — mehrere
  gleichzeitige Tool-Calls lösen zusammen genau eine Anfrage an den
  Token-Endpoint aus (manche Anbieter drosseln das).
- **Kein Retry-Sturm:** Lehnt der Token-Endpoint ab, bekommst du **einen**
  klaren Konfigurationsfehler mit dem HTTP-Status — JanuaPort versucht es nicht
  wieder und ruft das Zielsystem gar nicht erst an.
- **Ein Token je Connector**, nie über Connectoren hinweg geteilt.

**Bewusst nicht dabei** (dafür ist ein externer MCP-Server oder eine spätere
Story der Weg): der Benutzer-Login-Fluss (`authorization_code`), Discovery /
`.well-known`-Auflösung des Token-Endpoints, dynamische Client-Registrierung,
Client-Zertifikate (mTLS) und signierte Client-Assertions.

> **Wenn der Anbieter keine Gültigkeitsdauer nennt** (kein `expires_in` in der
> Antwort), speichert JanuaPort den Token bewusst nicht zwischen und holt für jeden
> Aufruf einen frischen — lieber ein Request mehr als eine erfundene Frist. In
> der Praxis kommt das nicht vor; falls doch, bitte melden.

### `tools[]`

| Feld | Pflicht | Bedeutung |
|---|---|---|
| `name` | ja | Tool-Name (Kleinbuchstaben, Ziffern, Unterstrich; beginnt mit Buchstabe). Eindeutig innerhalb des Connectors. |
| `description` | ja | **Wichtig:** Ein KI-Agent entscheidet allein anhand dieser Beschreibung, ob und wie er das Tool benutzt. Beschreibe, *was* zurückkommt, *welche* Filter es gibt, *Datumsformate* und *Pagination*. Englisch. |
| `params` | nein | Eingabeparameter (siehe unten). |
| `request` | ja | Der HTTP-Aufruf (siehe unten). |
| `headers` | nein | **Statische Request-Header** nur für dieses Tool. Sie überlagern die gleichnamigen Header der obersten Ebene (siehe [Statische Request-Header](#statische-request-header-headers)). |
| `response` | nein | JMESPath-Ausdruck, der die Antwort auf das Wesentliche projiziert. Ohne ihn wird die Antwort unverändert weitergegeben. |
| `response_file` | nein | Erklärt, dass die Antwort **eine Datei** ist und kein JSON. Die KI bekommt dann den daraus gewonnenen **Text** (siehe [Datei-Antwort](#datei-antwort-response_file)). Schließt `response` aus. |
| `check` | nein | `true` markiert dieses Tool als Probe für `jnpt connector check`. Höchstens ein Tool pro Connector. |
| `write` | nein | `true` markiert ein **schreibendes** (mutierendes) Tool. Erlaubt `request.method: POST` und verändert Berechtigung + Audit (siehe [Schreibende Tools](#schreibende-tools-write)). Default `false` = read-only. |

### `params[]`

| Feld | Pflicht | Bedeutung |
|---|---|---|
| `name` | ja | Parametername; zugleich der Platzhalter `{name}` im Request. |
| `description` | empfohlen | Beschreibung für den Agenten. |
| `type` | ja | `string`, `integer`, `number` oder `boolean`. |
| `required` | nein | `true` = Pflichtparameter. |
| `enum` | nein | Erlaubte Werte (nur bei `type: string`). |

### `request`

| Feld | Pflicht | Bedeutung |
|---|---|---|
| `method` | ja | `GET` (read-only) oder `POST` (nur bei `write: true`). PUT/PATCH/DELETE sind nicht im Format. |
| `path` | ja | Pfad relativ zur `base_url`, beginnt mit `/`. `{param}`-Platzhalter werden gefüllt und korrekt kodiert. |
| `query` | nein | Liste von `{name, value}`. `value` darf `{param}`-Platzhalter enthalten. Besteht der Wert nur aus einem Platzhalter und ist der zugehörige Parameter nicht gesetzt, entfällt der Query-Parameter ganz. |
| `encoding` | nein | Body-Kodierung. Leer = kein Body (GET). `multipart` = multipart/form-data (Datei-Upload, nur bei `POST`). `json` = application/json (JSON-Body, nur bei `POST`). |
| `body` | nein | Die multipart-Felder (nur bei `encoding: multipart`, siehe unten). |
| `body_json` | nein | Der JSON-Body als Struktur (nur bei `encoding: json`, siehe unten). Schließt `body` aus. |

## Statische Request-Header (`headers`)

Manche APIs verlangen einen festen Header, der nichts mit der Anmeldung zu tun
hat: eine API-Version, eine Mandanten-Kennung oder — der Auslöser dieses Felds —
das Antwort-Format. Microsoft Graph liefert Mail-Bodies nur dann als Klartext
statt HTML, wenn der Aufruf `Prefer: outlook.body-content-type="text"` trägt.

Dafür gibt es den optionalen `headers`-Block, auf **zwei Ebenen**:

```yaml
headers:                              # gilt für JEDEN Aufruf des Connectors
  X-Api-Version: "2024-10-01"

tools:
  - name: get_message
    description: Returns one message.
    headers:                          # gilt nur für DIESES Tool
      Prefer: 'outlook.body-content-type="text"'
    request:
      method: GET
      path: /v1.0/users/{mailbox}/messages/{message_id}
```

Beide Ebenen werden zusammengelegt; bei **gleichem Header-Namen gewinnt das
Tool** (Groß-/Kleinschreibung spielt dabei keine Rolle — in HTTP sind
Header-Namen unabhängig davon).

### Regeln (beim Start geprüft)

- **Nur feste Werte.** Es gibt hier **keine Platzhalter**: weder `{param}` noch
  `{{credential}}`. Beides ist ein Ladefehler, damit niemand glaubt, es würde
  ersetzt.
- ⚠️ **Ein Header trägt nie ein Secret.** Zugangsdaten gehen ausschließlich über
  `auth` — ein Weg, ein Vault-Zugriff, eine Stelle, an der redigiert wird. Wer
  einen API-Key als Header braucht, setzt ihn über `auth.header` +
  `auth.template` (genau dafür ist er da).
- **Diese vier Header gehören JanuaPort** und werden hier **abgewiesen** (mit einer
  Meldung, die sagt, wem sie gehören):

  | Header | Kommt von |
  |---|---|
  | `Authorization` | `auth.header` / `auth.template` (Credential aus dem Vault) |
  | `Content-Type` | `request.encoding` |
  | `Content-Length` | setzt Go selbst aus dem Body |
  | `Host` | ergibt sich aus `base_url` |

  Sie werden **nicht still ignoriert**: Die Spec lädt gar nicht erst. Genau das
  wäre sonst der Ausgang — ein hier gesetztes `Content-Length` würde beim Senden
  wortlos übergangen.
- **Ein Wert steht auf einer Zeile.** Ein Zeilenumbruch (oder ein anderes
  Steuerzeichen) im Wert ist ein Ladefehler: Er wäre der klassische Weg, einen
  zweiten Header einzuschmuggeln (Header-Injection).
- Ein Header ohne Wert ist ein Ladefehler (weglassen statt leer setzen).
- **`Accept` darfst du setzen** — er steht nicht auf der Liste. JanuaPort setzt von
  sich aus `Accept: application/json`; deklarierst du ihn ausdrücklich (z. B.
  `application/vnd.api+json`), gewinnt deine Angabe. Die Antwort muss trotzdem
  JSON sein, sonst scheitert das Response-Mapping.

**Nicht dabei und bewusst nicht geplant:** Header aus Tool-Parametern, berechnete
Werte, Vorlagensprache — und keine Auswertung von **Antwort**-Headern (etwas
ganz anderes).

## Platzhalter `{param}`

Jeder Platzhalter in `path` oder `query` muss einem deklarierten Parameter
entsprechen — sonst wird die Spec beim Start mit einer klaren Meldung
abgelehnt. Pfad-Platzhalter sind faktisch Pflicht (ohne Wert wäre der Pfad
kaputt); Query-Platzhalter dürfen für optionale Filter wegfallen.

## Response-Mapping (JMESPath)

Der optionale `response`-Ausdruck reduziert die Antwort auf das, was der Agent
braucht — das spart Kontext und macht Tools verständlicher. Beispiele
([JMESPath-Tutorial](https://jmespath.org/tutorial.html)):

| Antwort | `response` | Ergebnis |
|---|---|---|
| `{"content": [ ... ]}` | `content` | das innere Array |
| `{"content": [{"id":1,"x":9}]}` | `content[].id` | `[1]` |
| `{"data": {"items": []}}` | `data.items` | das Array |

### Was beim Agenten ankommt — Text-Block und `structuredContent`

Eine MCP-Antwort hat **zwei Träger**, und bei einem Listen-Ergebnis sind sie
seit #457 nicht mehr identisch:

- Der **Text-Block** trägt die Projektion **unverändert**. Eine Liste ist dort
  eine Liste — daran ändert sich nichts, und bestehende Agenten-Prompts, die
  diesen Text lesen, bleiben gültig.
- **`structuredContent`** trägt bei einem Listen-Ergebnis die Hülle
  **`{"items": […]}`**. Ein Objekt-Ergebnis steht dort unverändert.

```jsonc
// response: items  →  Projektion [{"id":"1"},{"id":"2"}]
"content":           [{"type":"text","text":"[{\"id\":\"1\"},{\"id\":\"2\"}]"}]
"structuredContent": {"items":[{"id":"1"},{"id":"2"}]}
```

**Warum die Hülle?** Weil die MCP-Spezifikation `structuredContent` als *„an
optional JSON object"* definiert. Eine Liste auf oberster Ebene ist spec-widrig:
Tolerante Clients (z. B. der claude.ai-Web-Client) schlucken sie, **strikte
verwerfen die komplette Antwort** — das Tool ist dort unbenutzbar, obwohl die
Daten korrekt sind. Es ist dieselbe Hülle wie `{"rows": […]}` bei den
Datenbank-Tools ([`docs/db-connector-spec.md`](db-connector-spec.md)); der
Schlüssel heißt hier `items`, weil ein REST-Treffer keine Datenbankzeile ist.

Ein leeres Ergebnis kommt als `{"items": []}` — „keine Treffer" ist eine gültige
Antwort und darf nicht wie ein Fehler aussehen.

⚠️ **Das ist eine Formänderung (#457).** Bis dahin stand die Liste ungehüllt in
`structuredContent`. Ein Agenten-Prompt, der ausdrücklich das *strukturierte*
Ergebnis als Liste erwartet, muss auf `items` nachziehen. Prompts, die den
Text-Block lesen (der Normalfall), sind nicht betroffen.

## Datei-Antwort (`response_file`)

Manche Endpunkte antworten nicht mit JSON, sondern mit **einer Datei** — ein
Mail-Anhang über Microsoft Graph (`…/attachments/{id}/$value`), ein Belegbild,
ein Dokument aus einer Dateiablage. Ein `response`-Ausdruck kann darauf nichts
zeigen: Es gibt kein JSON, auf das er passen würde.

Dafür gibt es `response_file`. Das Werkzeug erklärt damit: **meine Antwort ist
eine Datei.** JanuaPort liest die Bytes dann mit einem eigenen, höheren Deckel,
hält sie **nur im Speicher** und gibt der KI statt der Bytes den daraus
gewonnenen **TEXT**.

```yaml
  - name: read_attachment
    description: Returns the TEXT CONTENT of ONE attachment — never the bytes.
    headers:
      # Ohne diese Zeile sendet JanuaPort `Accept: application/json` —
      # und manche Dienste antworten dann mit einem Fehler statt mit der Datei.
      Accept: "*/*"
    params:
      - name: attachment_id
        description: Required. The attachment id.
        type: string
        required: true
    request:
      method: GET
      path: /v1.0/users/{mailbox}/messages/{message_id}/attachments/{attachment_id}/$value
    response_file:
      source: body        # der rohe Antwort-Body IST die Datei
```

`source: body` ist in dieser Version der einzige erlaubte Wert.

### Warum Text und nicht die Datei selbst

Weil eine Datei im Chat niemandem hilft. Ein Browser-Client (ChatGPT,
claude.ai) kann aus einem base64-Block keine Datei auf eine Platte schreiben,
und ob er einen Blob dem Modell überhaupt zeigt, ist unbelegt. **Text ist das,
womit eine KI arbeiten kann** — und das Einzige, woran sich später
pseudonymisieren lässt: Bytes lassen sich nicht pseudonymisieren.

Die Bytes berühren dabei **nie** Dateisystem, Log, Audit oder eine
Fehlermeldung. Es gibt keinen Download, keinen Link, keinen Zwischenspeicher.

### Was ankommt

Immer ein Objekt mit denselben Feldern — auch wenn nichts zu lesen war:

| Feld | Bedeutung |
|---|---|
| `name` | Dateiname, falls der Dienst einen `Content-Disposition` sendet, sonst leer |
| `mime` | der aus den **Bytes** erkannte Typ |
| `declared_mime` | der Typ, den der Dienst **behauptet** hat |
| `bytes` | Größe der abgerufenen Datei |
| `kind` | `pdf`, `xml`, `json`, `csv`, `text` oder `unbekannt` |
| `readable` | ob Inhalt geliefert wird — `false` heißt: nicht raten |
| `text` | der gewonnene Inhalt |
| `truncated` | ob gekürzt wurde |
| `text_bytes_total` | Länge des Textes vor dem Zuschnitt |
| `note` | die ehrliche Erklärung, wenn (nicht vollständig) gelesen werden konnte |
| `embedded[]` | in einem PDF eingebettete Dateien — bei einer E-Rechnung das XML |

Gelesen werden in dieser Version: **PDF-Textebene**, **in einem PDF eingebettete
Dateien** (ZUGFeRD/Factur-X — das XML ist für eine KI die belastbare Quelle für
Beträge und Rechnungsnummern), **XML, JSON, text/plain, text/csv**. Word, Excel,
Bilder, `.eml` und ZIP kommen mit `readable: false` plus Typ und Größe zurück.
Ein **gescanntes PDF** hat keine Textebene: leerer Text und eine Notiz, die das
sagt — **es gibt kein OCR**.

⚠️ **Ehrlich zur Qualität:** PDF-Textextraktion bewahrt die WÖRTER, nicht das
Layout. Mehrspaltige Seiten können verweben, Tabellen verlieren ihre Struktur,
und bei ungewöhnlichen Schriften werden Umlaute zu Ersatzzeichen. Das reicht für
„was steht in dieser Rechnung", nicht für „lies mir die Positionszeilen exakt
aus". Bei einer E-Rechnung ist das zweitrangig: Dort steht die Wahrheit im
eingebetteten XML.

### Die Grenzen (beim Start geprüft)

- `response` und `response_file` **schließen sich aus** — eine Projektion auf
  eine PDF-Datei wäre eine Falschaussage.
- Nur **lesend**: kein `write: true`, kein `POST`, kein Request-Body.
- Kein `check: true` — der Probe-Aufruf von `jnpt connector check` darf keine
  fremde Datei ziehen und durch einen Parser schicken.
- **Ein Aufruf, eine Datei.** Es gibt keinen Sammel-Abruf.

### Die Deckel

Sie stehen **fest im Programm** und sind bewusst nicht in der YAML einstellbar —
ein hochgesetzter Deckel wäre der Weg, auf dem eine einzige Datei den Gateway
für alle kippt.

| Deckel | Wert | Verhalten |
|---|---|---|
| Dateigröße | 10 MiB | **fail-closed** — eine größere Datei wird abgelehnt, nicht halb gelesen |
| Text | 128 KiB | **gekürzt** plus `truncated: true` und `text_bytes_total` |
| Seiten je PDF | 500 | die Seitenschleife endet dort |
| eingebettete Dateien | 5, je 1 MiB | mehr wird nicht gelesen |
| Auswertungszeit | 20 s | danach ein sauberer Fehler |

Der Unterschied zwischen „ablehnen" und „kürzen" ist Absicht: Bei der
Dateigröße wäre ein halb gelesenes PDF eine **Falschaussage**. Beim Text hat der
Agent keinen Hebel, mit dem er weniger anfordern könnte — dort wäre ein Fehler
nur eine unbenutzbare Datei.

## Schreibende Tools (`write`)

Standardmäßig sind Tools read-only. Ein **schreibendes** Tool markiert man mit
`write: true`; es darf dann `request.method: POST` mit einem
**multipart/form-data**-Body (Datei-Upload, dieser Abschnitt) oder einem
**JSON-Body** ([`encoding: json`](#json-body-encoding-json)) verwenden. Mehr
Schreib-Formen gibt es im Format nicht — bewusst eng: additiv und umkehrbar
(z. B. „Beleg in die Inbox legen", „Entwurf anlegen"), nie „final
verbuchen/löschen".

```yaml
tools:
  - name: upload_voucher_file
    description: >
      Uploads a receipt FILE into the inbox. This is a WRITE action — a human
      must confirm before calling. The file is base64 in "content" (max 5 MiB
      decoded); provide "filename" and "content_type". Returns the new file id.
    write: true                       # markiert das Tool als schreibend
    params:
      - name: content
        description: The file content, base64-encoded. Max 5 MiB decoded.
        type: string                  # der Datei-Inhalt ist IMMER ein string (base64)
        required: true
      - name: filename
        description: The file name shown upstream.
        type: string
        required: true
    request:
      method: POST                    # nur bei write: true erlaubt
      path: /v1/files
      encoding: multipart             # multipart/form-data
      body:
        - name: type                  # Textfeld: fester Wert (oder {param})
          value: voucher
        - name: file                  # File-Feld: genau EINES pro Tool
          file: content               # Name des string-Parameters mit base64-Inhalt
          filename: "{filename}"      # Content-Disposition (darf {param} enthalten)
          content_type: application/pdf  # MIME-Typ (darf {param} enthalten)
    response: "{id: id}"
```

### `body[]` — multipart-Felder

| Feld | Pflicht | Bedeutung |
|---|---|---|
| `name` | ja | Form-Feld-Name im multipart-Body, z. B. `type` oder `file`. |
| `value` | bei Textfeld | Textwert (mit optionalen `{param}`-Platzhaltern). **Entweder** `value` **oder** `file`, nie beides. |
| `file` | bei File-Feld | Name des `string`-Parameters, dessen **base64**-Wert den Datei-Inhalt liefert. **Genau ein** File-Feld pro Tool. |
| `filename` | bei File-Feld | Dateiname im Content-Disposition (mit optionalen `{param}`-Platzhaltern). |
| `content_type` | bei File-Feld | MIME-Typ des File-Parts (mit optionalen `{param}`-Platzhaltern). |

**Regeln (beim Start geprüft):** `POST` ⇔ `write: true`; `encoding: multipart`
verlangt `POST` + nicht-leeren `body`; je Feld entweder Text **oder** Datei;
genau **ein** File-Feld; der File-Quell-Parameter ist `type: string`; alle
`{param}` in `value`/`filename`/`content_type` zeigen auf deklarierte Parameter.

Ein **nur-File-Body** (ein File-Feld, kein Textfeld) ist gültig — die Regel
verlangt nur einen nicht-leeren Body mit genau einem File-Feld. Und der `path`
darf wie bei jedem Tool `{param}`-Platzhalter tragen: So heftet z. B. das
Lexware-Tool `attach_file_to_voucher` (`POST /v1/vouchers/{voucher_id}/files`,
nur das File-Feld) ein Belegbild an einen bestehenden Beleg, während
`upload_voucher_file` (`POST /v1/files` mit `type=voucher`) ein neues Dokument in
die Inbox legt. Inbox vs. anheften: `get_voucher` liefert ein `files`-Array
(IDs angehängter Dokumente); ein **leeres** `files`-Array = kein Belegbild → mit
`attach_file_to_voucher` an genau diesen Beleg anheften, nicht mit
`upload_voucher_file` (das legt ein separates, neues Inbox-Dokument an).

### Datei-Inhalt, Größe, Retries

- Der **Datei-Inhalt** wird als **base64-String** übergeben (kein Sondertyp).
  JanuaPort dekodiert ihn, prüft die Größe und sendet ihn als File-Part. Maximal
  **5 MiB** nach dem Dekodieren — sonst ein Argument-Fehler an den Agenten.
- **Keine Retries** bei Schreib-Tools: Ein POST ist nicht idempotent (ein Retry
  lüde einen zweiten Beleg hoch). Bei einem Fehler wird **nicht** automatisch
  wiederholt.
- Der Datei-Inhalt erscheint **nie** in einem Log, einer Fehlermeldung oder im
  Audit-Event (der Quell-Parameter wird automatisch redigiert — siehe unten).

### Berechtigung, Bestätigung, Audit

- **Tool-genauer Scope nötig:** Ein schreibendes Tool wird von einem
  connector-weiten Scope (`connector`) **nicht** miterfasst — es verlangt einen
  ausdrücklichen `connector:tool`-Eintrag (`jnpt token allow <id>
  lexware-office:upload_voucher_file`). „Gib dem Token Lexware" gibt damit nie
  versehentlich Schreibrechte.
- **Bestätigung:** Schreibende Tools tragen MCP-Annotations
  (`readOnlyHint:false`), sodass ein Client (z. B. Cowork) vor dem Aufruf
  nachfragen kann. Schreibe in die Description ausdrücklich, dass ein Mensch
  bestätigen muss.
- **Audit:** Der Aufruf wird als schreibend markiert (`jnpt audit list --write`).
  Scheitert das Schreiben des Audit-Events **nach** dem Upload, sieht der Agent
  einen Fehler, obwohl die Datei evtl. schon hochgeladen wurde — die Meldung
  bittet dann, im Zielsystem zu prüfen, statt blind zu wiederholen.

## JSON-Body (`encoding: json`)

Die meisten modernen APIs nehmen Schreib-Aufrufe als **JSON** entgegen. Dafür
gibt es die zweite Body-Form: `encoding: json` plus `body_json` — der Body wird
im YAML als **Struktur** beschrieben (Felder, verschachtelte Objekte, Listen),
mit `{param}`-Platzhaltern in den Textwerten.

```yaml
tools:
  - name: create_draft
    description: >
      Creates a DRAFT email in the user's mailbox — it is NOT sent. This is a
      WRITE action; a human must confirm before calling.
    write: true                       # JSON-Body ist immer ein Schreibvorgang
    params:
      - name: mailbox
        description: The mailbox address the draft is created in.
        type: string
        required: true
      - name: subject
        description: The subject line.
        type: string
        required: true
      - name: content
        description: The message body as plain text.
        type: string
        required: true
      - name: recipient
        description: The recipient's email address.
        type: string
        required: true
      - name: reply_to
        description: Optional reply-to address.
        type: string
    request:
      method: POST                    # nur bei write: true erlaubt
      path: /v1.0/users/{mailbox}/messages
      encoding: json                  # Content-Type: application/json
      body_json:
        subject: "{subject}"          # Platzhalter im Textwert
        importance: normal            # konstanter Text aus dem YAML
        isDraft: true                 # konstante Werte behalten ihren Typ
        body:
          contentType: Text           # verschachteltes Objekt
          content: "{content}"
        toRecipients:                 # Liste mit fester Länge
          - emailAddress:
              address: "{recipient}"
        replyTo:
          - emailAddress:
              address: "{reply_to}"   # optional — siehe „Weggelassene Werte"
    response: "{id: id}"
```

### Regeln (beim Start geprüft)

- `encoding: json` verlangt **`method: POST`** und damit **`write: true`** —
  ein JSON-Body ist immer ein Schreibvorgang.
- `body_json` und `body` (multipart) **schließen sich aus**: ein Tool sendet
  einen Body, nicht zwei.
- Die **oberste Ebene ist ein Objekt** (`feld: wert`). Ein einzelner Text oder
  eine Liste als ganzer Body ist nicht vorgesehen.
- **Kein leeres Objekt und keine leere Liste** — irgendwo im Baum. Ein leerer
  Container in der Spec ist immer ein Versehen.
- **Feldnamen sind Text und tragen keine Platzhalter.** `{param}` wird nur in
  **Werten** ersetzt, nie in Feldnamen (sonst stünde er still im Body).
- Jeder `{param}` in einem Textwert muss einem **deklarierten Parameter**
  entsprechen — sonst wird die Spec beim Start abgelehnt, mit dem genauen Pfad
  zum Problem (z. B. `tools[0].request.body_json.toRecipients[0].emailAddress.address`).
- Werte, die JSON nicht kennt, werden abgelehnt. Praktischer Stolperstein:
  **Datumsangaben in Anführungszeichen setzen** (`"2026-01-31"`) — unquotiert
  liest YAML sie als Zeitstempel.

### Weggelassene Werte (optionale Parameter)

Wie bei den Query-Parametern gilt: Ein Textwert, dessen Platzhalter auf einen
**nicht gesetzten optionalen Parameter** zeigt, **entfällt**. Das setzt sich
nach oben fort:

- Das Feld bzw. der Listen-Eintrag verschwindet — die Liste wird kürzer, sie
  bekommt nie eine Lücke.
- Ein Objekt oder eine Liste, die dadurch **alle** ihre Werte verliert,
  entfällt ebenfalls. Im Beispiel oben: ohne `reply_to` fehlt nicht nur die
  Adresse, sondern das ganze `replyTo`-Feld.
- Bleibt am Ende gar nichts übrig, wird `{}` gesendet.
- Konstante Werte aus dem YAML (`normal`, `true`, Zahlen) bleiben immer stehen.

### Grenzen (v1)

- **Werte aus Parametern sind immer Text.** `"{page}"` mit einem
  `integer`-Parameter landet als `"7"` im JSON, nicht als `7`. Wo die API eine
  echte Zahl oder ein `true` braucht, muss der Wert im YAML **konstant** sein.
- **Listen haben feste Länge**: Aus einem Parameter lassen sich keine Einträge
  erzeugen.
- Kein `form-urlencoded`, kein PUT/PATCH/DELETE, keine mehrstufigen Abläufe —
  dafür ist ein externer MCP-Server der Weg.

Berechtigung, Bestätigung und Audit sind identisch zum Datei-Upload (siehe
oben): tool-genauer Scope, `readOnlyHint:false`, Kennzeichnung als Write. Die
Body-Werte sind normale Tool-Argumente — sensible Felder gehören wie überall in
`redact_params`.

> **Warum eine Struktur und kein JSON-Text?** JanuaPort baut den Body aus dieser
> Struktur und kodiert ihn erst zum Schluss. Nur so landen Anführungszeichen,
> Backslashes, Zeilenumbrüche und Umlaute aus einem Parameterwert **korrekt
> maskiert** im JSON. Wäre der Body ein Text-Template, könnte ein Wert wie ein
> Firmenname mit `"` die Struktur zerreißen — oder heimlich Felder ergänzen, die
> in der Spec gar nicht stehen. Deshalb gibt es kein „JSON als Freitext".

## Audit & Redaction (`redact_params`)

Jeder Tool-Aufruf, der den Dispatch erreicht, wird protokolliert (`jnpt audit
list`, siehe README; Aufrufe auf out-of-scope-/unbekannte Tools weist das
MCP-SDK davor ab und erzeugen derzeit keinen Eintrag — bekannte Einschränkung
#53). Das Audit-Event speichert die **Tool-Argumente** als JSON — nie Header
oder das Credential. Sind einzelne Argumente trotzdem sensibel (z. B. eine Personen-ID
oder ein Suchbegriff mit PII), nimm ihre Namen in `redact_params` auf:

```yaml
redact_params: [from, customer_id]
```

Die gelisteten Parameter erscheinen im Audit-Log dann als `"[REDACTED]"` —
der Wert verlässt den Prozess nicht. Die Liste gilt **connector-weit**: Ein
Name wird in jedem Tool dieses Connectors redigiert, das ihn als Parameter hat.

> **Automatisch redigiert:** Bei einem schreibenden Datei-Upload-Tool wird der
> File-Quell-Parameter (der base64-Inhalt) **immer** redigiert — unabhängig von
> `redact_params`. Der Datei-Inhalt landet so nie im Audit-Log. `filename` und
> `content_type` bleiben Klartext (nützliche Metadaten, kein Inhalt).
Jeder Eintrag muss ein in **irgendeinem** Tool deklarierter Parameter sein —
ein Tippfehler wird beim Start abgelehnt (sonst würde im Glauben an Schutz nichts
redigiert). Mehr als diese Feldnamen-Liste kann Redaction v1 bewusst nicht
(keine Muster, keine Wert-Heuristik).

## Privacy Mode (`privacy`) — Feld-Tokenisierung (Epic #78)

Ein Tool kann einzelne Felder als **privacy-relevant** markieren. Beim **Lesen**
ersetzt JanuaPort diese Werte durch **deterministische, tenant-weit konsistente
Tokens**, bevor die Antwort die KI erreicht; bei einer **Write**-Operation
detokenisiert JanuaPort sie wieder, bevor der Request upstream geht. So orchestriert
die KI einen Prozess (lesen → schreiben, auch quellen-übergreifend matchen),
**ohne den Klartext je zu sehen**.

> **Seit #343 braucht die Rückwandlung keine Deklaration mehr.** Sie ist der
> Standard, wirkt in allen String-Parametern und über Integrationen hinweg;
> abgeschaltet wird sie in der Betreiber-Oberfläche je Integration/Werkzeug. Der
> `write:`-Block unten **lädt weiterhin, steuert aber nichts mehr** — neue Specs
> deklarieren ihn nicht. Begründung und Preis: `docs/privacy-mode.md` §4.

```yaml
tools:
  - name: get_contact
    description: Returns one contact by id.
    request: { method: GET, path: /v1/contacts/{id} }
    privacy:
      read:
        - { field: name, label: name }   # Antwort-JSON-Schlüssel → semantisches Label
        - { field: iban, label: iban }

  - name: create_contact
    description: Creates a contact.
    write: true
    params:
      - { name: display_name, type: string, required: true, description: "…" }
    request: { method: POST, encoding: multipart, path: /v1/contacts, body: [...] }
    privacy:
      write:
        - { field: display_name, label: name }   # Ziel-PARAMETER → Label
```

Die KI sieht beim Lesen statt des Werts ein Token in der Form **`‹label-id›`**
(z. B. `‹name-7f3a91b2c4d5e6f708192a3b›`). Das Label bleibt sichtbar, damit die KI
semantisch weiterarbeiten kann; sie kann das Token als Ganzes in Freitext
einbetten und in ein deklariertes Write-Zielfeld zurückschreiben.

**Felder:**
- `read[]`: `field` ist ein **JSON-Objektschlüssel** der (gemappten) Antwort;
  JanuaPort tokenisiert jeden passenden Schlüssel mit **nicht-leerem String-Wert**,
  rekursiv auch in Arrays/verschachtelten Objekten (typische Listen-Antworten).
- `write[]`: `field` ist der Name eines **deklarierten `type: string`-Parameters**;
  in seinem Wert werden gefundene Tokens detokenisiert.
- `scan[]` (s. u.): `field` ist ein **JSON-Objektschlüssel** der Antwort, dessen
  Freitext nach Muster-Treffern **durchsucht** statt ersetzt wird.
- `label` ist ein semantischer Bezeichner (`name`, `iban`, `email`,
  `steuernummer`, …): beginnt mit Kleinbuchstabe, danach nur `a-z 0-9 _`. Der
  Schlüssel wird aus dem Label abgeleitet — **gleiches Label über Connectoren =
  gleiches Token** (tenant-weite Joins). Verschiedene Labels ergeben unkorrelierte
  Tokens (Frequenzschutz).

### `scan` — Muster-Treffer INNERHALB eines Freitextfelds (Story #336)

`read` ersetzt einen **ganzen** Feldwert. Für Freitext reicht das nicht: Der
Verwendungszweck eines Bankumsatzes trägt regelmäßig genau die IBAN, die nebenan
schon pseudonymisiert ist. `scan` schließt diese Lücke für **strukturierte**
Werte — es ersetzt **nur die Treffer**, der Rest des Textes bleibt wörtlich stehen.

```yaml
    privacy:
      read:                                   # ganzer Feldwert
        - { field: counter_account, label: iban }
      scan:                                   # Treffer INNERHALB des Feldwerts
        - { field: purpose, patterns: [iban, steuernummer] }
```

Ergebnis: `"purpose": "RE 2026-0001 Zahlung an ‹iban-62b3c4b045ff90eca2a6de09›"`.

**Der Muster-Name IST das Label** — es gibt hier bewusst **kein** `label:` (ein
solches Feld ist ein Ladefehler). Damit ergibt derselbe IBAN-Wert im
`read`-deklarierten Feld und als `scan`-Treffer **dasselbe Pseudonym**: Der Agent
kann den Verwendungszweck gegen den Beleg matchen, ohne dass jemand etwas
konsistent halten muss.

**Verfügbare Muster (geschlossener Katalog, kein freier Regex):**

| Muster | Trifft | Trifft bewusst NICHT |
|---|---|---|
| `iban` | kompakte IBAN mit gültiger Prüfsumme (`DE89370400440532013000`) | gruppierte Schreibweise (`DE89 3704 …`), Prüfsummen-Fehler, Zahlenkolonnen |
| `email` | `max.mustermann@example.com` | `user@localhost` (keine TLD) |
| `steuernummer` | USt-IdNr nur in **kompakter** DE-Form (`DE123456789`), geteilte Steuernummer `12/345/67890` | **gruppierte** Schreibweise (`DE 123456789`), **jedes Nicht-DE-Präfix** (`ATU…`, `FR…`, `NL…`), nackte 10/11-stellige Ziffernkolonne (= Beleg-/Kundennummer) |
| `geburtsdatum` | `15.03.1990`, `1990-03-15` — **nur Jahr 1900–2015** | Gegenwartsdaten wie `15.04.2026` / `2026-04-15` (Rechnung, Fälligkeit, Valuta), zweistellige Jahre, `2026-0001`, Zeitstempel-Anhänge |
| `telefon` | `+49 30 12345678`, `0511/1234567` | nackte Ziffernkolonnen, zu kurze Nummern |

**Regeln:**
- **Deny-by-default:** Nur unter `scan` gelistete Felder werden durchsucht. Es
  gibt keinen Scan „über alles".
- Ein Feld steht **entweder** in `read` **oder** in `scan`, nie in beiden.
- Muster-Namen müssen aus dem Katalog stammen; ein Tippfehler ist ein
  **Ladefehler** (die Meldung zählt die verfügbaren Muster auf).
- **Kein Treffer = Feld unverändert.** Der Rückweg braucht nichts Neues: Ein
  zurückgeschickter Freitext mit eingebettetem Tag wird wie immer detokenisiert
  (das Ziel-Feld muss dafür unter `write` stehen).
- **Es gibt kein `name`- und kein `adresse`-Muster** (und wird keines geben). Ein
  Muster kann dafür nicht halten, was ein Katalogeintrag verspricht: „Müller GmbH"
  trifft man, „Musterküchen am Markt, Inh. M. Muster" nicht. Ein solcher Eintrag
  erzeugte den gefährlicheren Zustand — es *sähe* pseudonymisiert aus.
- **`geburtsdatum` erkennt die FORM eines Datums plus einen plausiblen
  Jahresbereich (1900–2015, fest gesetzt), nicht seine Bedeutung.** Dadurch fallen
  Rechnungs-, Fälligkeits- und Valutadaten heraus — genau die Angaben, mit denen
  der Agent arbeitet. Ein **altes Vertragsdatum oder Gründungsjahr** aus dem
  Fenster wird weiterhin getroffen: nicht blind auf jedes Freitextfeld legen.
- **Der Honigtopf wächst schneller:** ein Eintrag je **Treffer** statt je
  deklariertem Feld (`docs/privacy-mode.md` §6).

**Sicherheit & Grenzen (verbindlich):**
- ~~**Scope-gebundene Reversal**~~ — **mit #343 aufgegeben** (PO-Entscheid,
  `docs/privacy-mode.md` §4). Ein Token aus Connector A wird in einem Write nach
  B **aufgelöst**; die Rückwandlung ist der Standard und wirkt über
  Integrationen hinweg. Der Abschalter dafür sitzt in der Betreiber-Oberfläche,
  nicht in der Spec: er ist eine Entscheidung über die ZIELSYSTEME des
  Betreibers, keine Hersteller-Vorgabe.
- **Fail-closed bei unbekanntem/verfälschtem Token** (`ArgumentError`
  „unbekanntes Pseudonym"): nie das Roh-Token senden, nie raten. Neuer Klartext
  (kein Token) läuft wörtlich durch. **Seit #343 ist das die letzte
  fail-closed-Kante des Write-Pfads.**
- **Klartext nie** in Log/Audit/Antwort. Jede Rückwandlung wird auditiert — mit
  dem Pseudonym (`‹label-id›`), dem Ziel-Connector und dem Ziel-Tool, nie dem
  Klartext. Seit #343 ist das die einzige verbliebene Sichtbarkeit auf den
  Vorgang.
- **Nur String-Felder** (v1). Keine Zahlen-Operanden, keine partielle Maskierung.
  Freitext ist seit #336 über `scan` erreichbar — aber nur so weit, wie ein
  **kuratiertes Muster** trägt; was es nicht trifft, bleibt im Klartext.
- **Deny-by-default:** nur explizit gelistete Felder werden je angefasst.
- **Frequenz-Schutz:** Bei niedrig-kardinalen Feldern (z. B. ein Status mit
  wenigen Werten) sind Tokens per Häufigkeit rückschließbar — flagge nur echte
  Pass-through-Identitäten (Name, IBAN, Adresse, Kunden-/Steuernummer, E-Mail).
- **Ehrliche Grenze:** Privacy Mode funktioniert für Werte, die die KI **trägt/
  matcht**, nicht für Werte, über die sie **urteilen** muss (Schwellwerte, Summen).
  Details: `docs/compliance-roadmap.md`.

## Validierung & Probe

```bash
jnpt connector check               # alle Connectoren prüfen
jnpt connector check demo-erp      # nur einen
```

Vier Stufen pro Connector: (1) Spec gültig, (2) Auth-Werte ausgefüllt — kein
Vorlagen-Platzhalter mehr in `auth.token_url`/`auth.client_id` (Story #709; nur
bei `auth.type: oauth2_client_credentials` relevant, siehe
[App-only-Token](#app-only-token-authtype-oauth2_client_credentials)), (3)
referenziertes Credential im Vault vorhanden, (4) Probe-Aufruf gegen die echte
API (das `check: true`-Tool bzw. das erste Tool ohne Pflichtparameter). Schlägt
eine Stufe fehl, sagt die Ausgabe genau welche — Exit-Code ≠ 0 macht das
skriptbar.

**Redigierter Fehler-Body bei 4xx (Diagnose).** Lehnt das Zielsystem den
Probe-Aufruf mit einem **4xx** ab (z. B. `400` wegen einer Validierung), zeigt
`jnpt connector check` zusätzlich den **redigierten** Antwort-Body des
Zielsystems an (`Antwort des Zielsystems (redigiert): …`). Das nennt den Grund
oft direkt — statt nur „HTTP 400" zu sehen. Der Body wird vor der Anzeige
bereinigt: das Credential und der Auth-Header erscheinen **nie** (auch dann
nicht, wenn das Zielsystem sie im Fehler zurückspiegelt), bekannte
Secret-Felder (`token`, `password`, `api_key`, …) werden zu `[REDACTED]`
maskiert, und die Ausgabe ist auf eine kompakte Zeile längenbegrenzt.

Wichtig: Diesen Body bekommt **nur** der lokale Diagnose-Pfad (`connector
check`). Im normalen Tool-Pfad an den KI-Agenten bleibt es bei der knappen,
body-freien Fehlermeldung (Status + Erklärung) — ein Upstream-Body landet nie in
einer Tool-Antwort.

## Live-Selbsttest

```bash
jnpt connector selftest            # alle Connectoren live testen
jnpt connector selftest demo-erp   # nur einen
```

Während `connector check` **statisch** in Stufen prüft, fällt `connector
selftest` das **Live-Urteil**: ist der Connector *jetzt* gegen die echte API
funktionsfähig? Er führt das repräsentative Tool aus (dasselbe wie `check`: das
`check: true`-Tool bzw. das erste ohne Pflichtparameter; gibt es keins, wird der
Test **übersprungen** — kein Fehler) und beurteilt das Ergebnis:

1. **Erreichbarkeit/Auth/Status:** Der Aufruf liefert einen Erfolg (2xx). Ein
   Timeout, 4xx/5xx oder eine zu große Antwort ist ein Fehlschlag (`upstream_error`);
   ein fehlendes Credential ist `config_error` (wie bei `check`).
2. **Form-Check (leicht):** Die Antwort ist **gültiges JSON** **und** die
   `response`-Projektion (JMESPath) löst zu einem **nicht-leeren** Wert auf (nicht
   `null`, kein leeres Array/Objekt, kein leerer String). Schlägt das fehl, ist es
   ein `form_error` — der Aufruf kam zwar durch, lieferte aber nicht die erwartete
   Form. Ein skalarer Wert wie `0`/`false` gilt als vorhanden.

Der **Form-Check ist bewusst leicht** — er prüft, dass die `response`-Projektion
überhaupt etwas auflöst, **kein** vollständiges Antwort-Schema (das ist eine
spätere Drift-Erkennung). Er nutzt nur das, was die Spec ohnehin hat (`check:
true`-Tool + `response`-Projektion); **keine neuen YAML-Felder**.

Der Selbsttest ist **extern getriggert** (es gibt **keinen** eingebauten
Scheduler): Cron, CI oder die Admin-GUI rufen ihn in beliebiger Kadenz. Exit-Code
≠ 0 bei Fehlschlag macht die CLI skriptbar; der **Grund** eines Fehlschlags ist
wie überall **body- und secret-frei** (Status + knappe Erklärung, nie ein
Upstream-Body, nie das Credential — auch wenn das Zielsystem es zurückspiegelt).
Dasselbe Urteil liefert `POST /api/admin/connectors/{name}/selftest` (für die GUI
und externe Trigger), siehe `docs/admin-api.md`.

## Vertrags-Tests (CI) — „Prod-Fehler → neuer Golden-Test"

Jeder Connector bekommt einen **Vertrags-Test** in CI: Ein Golden-Test schreibt
den **ausgehenden** Request-Envelope jedes Tools fest — Methode, Pfad (mit
gefülltem/escaptem `{param}`), Query (inkl. „optionaler Parameter weggelassen"),
die relevanten Header (`Accept: application/json`, bei multipart `Content-Type`
und **jeden in der Spec deklarierten statischen Header**), die Body-Form
schreibender Tools (multipart-Felder, genau eine Datei) — plus die
JMESPath-Projektion gegen eine Beispielantwort. Der Test läuft
**ohne echten Account** gegen einen lokalen Test-Server und ist deshalb in jeder
CI grün/rot reproduzierbar. Credentials sind dabei nie im Spiel: Der Test nutzt
ein Dummy-Secret, und die eingecheckten Golden-Dateien enthalten **nie** ein
Secret oder echte Daten (der Auth-Header erscheint nur redigiert).

Das ist das Herzstück der **Antifragilität**: Tritt in Produktion ein Fehler auf
(z. B. ein Zielsystem, das ohne `Accept`-Header mit 400 antwortet — ein real
passierter Fall), wird er **einmal** als neuer Golden-Test nachgestellt. Danach
schlägt jede Regression dieses Verhaltens sofort in CI fehl — derselbe Fehler
kann nie wieder unbemerkt zurückkommen. Wie man einen Vertrag für einen neuen
Connector hinzufügt, steht in `internal/connector/runtime/CLAUDE.md` (Abschnitt
„Contract-/Golden-Test-Harness"); das Harness selbst liegt in
`internal/connector/contracttest`.

## Wann ist dieses Format *nicht* das richtige Werkzeug?

Das Format beschreibt bewusst **einen einfachen GET-Aufruf pro Tool** plus
**zwei** schreibende Formen (POST + Datei-Upload, POST + JSON-Body). Wenn du
andere Schreiboperationen (PUT/PATCH/DELETE), mehrstufige Abläufe (erst
Login-Token holen, dann Daten), das Hochladen mehrerer Dateien, automatisches
Durchblättern aller Seiten oder komplexe Umformungen brauchst, ist ein
**eigener (externer) MCP-Server** der bessere Weg — JanuaPort bindet ihn genauso mit
Auth und Audit an. Im Zweifel: kleiner halten und nachfragen.

Und wenn das Bestandssystem **gar keine brauchbare API hat**, aber eine
Datenbank, in die du lesen darfst: Dafür gibt es die dritte Integrationsart,
**hinterlegte SELECT-Abfragen als MCP-Tools** —
[`docs/db-connector-spec.md`](db-connector-spec.md) (read-only, PostgreSQL).
Wo es eine API gibt, ist sie trotzdem vorzuziehen: Eine API ist ein Vertrag, ein
Datenbankschema nicht.
