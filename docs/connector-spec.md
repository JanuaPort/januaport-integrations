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
> [JSON-Body](#json-body-encoding-json). Eine API, die auch LESEN per `POST` mit
> JSON-Body verlangt (Odoo JSON-2, GraphQL, Suche per POST), bindest du mit
> `read_via_post: true` als **Lese-Werkzeug** an — siehe
> [Lesender POST](#lesender-post-read_via_post). Alles andere (PUT/PATCH/DELETE,
> mehrere Dateien) bleibt dem externen MCP-Server vorbehalten.

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
| `name` | ja | Eindeutiger Connector-Name. Wird zum **Prefix** jedes Tool-Namens (`demo_erp_list_invoices`). Bindestriche werden zu Unterstrichen. ⚠️ **Heute gilt:** Ein Name, der nach dieser Normalisierung kein gültiges Präfix ergibt (Großbuchstaben, Umlaute, Punkt, Leerzeichen, führende Ziffer), wird bei der **Anlage über die Admin-Fläche abgelehnt**; ein solcher Name im **Bestand** hält den Start NICHT auf, erzeugt aber beim Start eine **WARN-Zeile** mit Namen und Grund. Umbenannt wird nichts automatisch — ein Rename berührt Scopes, Tokens und Team-Zuordnungen. **Reserviert** (das Gateway belegt diese Namen selbst — eine Integration dieses Namens verhindert den Start): `memory`, `kartei`, `usecase`, `graph`, `freigabe` und das Präfix `freigabe_`, `teamdoc` und das Präfix `teamdoc_`, `wissen`, `ablage`, `etl` (bei Team-Specs auch das Präfix `etl_`; ein **Bestand** `etl` startet, wird aber nicht geladen und per Warnung, Audit und Mail gemeldet), `ping`, `catalog`, `report_problem`. Die Liste ist nicht abschließend: Das Gateway sperrt außerdem Namen und Präfixe für seine eigenen Werkzeugfamilien, unter anderem `app`, `skript`, `script`, `agent`, `desktop` sowie die Präfixe `app_`, `skript_`, `script_`, `agent_`, `desktop_`, `freigabe_`, `teamdoc_` und `run_control_`; ein Treffer verhindert den Start bzw. wird bei der Anlage abgewiesen. |
| `version` | **ja** | Fassung dieser Spec als **SemVer** `MAJOR.MINOR.PATCH`, in Anführungszeichen (`"1.0.0"`). Kein führendes `v`, kein `-beta`, kein `+build`, keine führenden Nullen. Fehlt sie oder ist sie ungültig, lädt die Spec **nicht** (siehe [Warum `version` Pflicht ist](#warum-version-pflicht-ist)). |
| `instance` | nein | Deklarierte Anlagenwerte für Header und Pfade; siehe unten. |
| `base_url` | ja | Basis-URL der API (`http://` oder `https://` mit Host). |
| `auth` | ja | Wie das Credential in jeden Request kommt (siehe unten). |
| `headers` | nein | **Statische Request-Header** für jeden Aufruf dieses Connectors (siehe [Statische Request-Header](#statische-request-header-headers)). Feste Werte oder deklarierte `{{instance.<name>}}`-Marken. |
| `timeout` | nein | Zeitlimit pro Aufruf, z. B. `30s`, `1500ms`. Default 30s, Obergrenze 120s. |
| `min_interval` | nein | Mindestabstand zwischen zwei Aufrufen dieses Connectors (z. B. `500ms` bei ~2 Anfragen/Sekunde). Verhindert, dass das Zielsystem drosselt. |
| `redact_params` | nein | Liste von Parameter-Namen, deren Werte im **Audit-Log** als `[REDACTED]` erscheinen — auf der Protokolltiefe „Metadaten" (Default); darüber stehen sie im Inhalt (siehe unten). |
| `endpoint_view` | nein | `true` macht diesen Connector zu einem eigenen **benannten MCP-Endpoint** `/mcp/v/<name>` (#164) — der Client sieht dann NUR die Tools dieses Connectors als eigene „Integration" (kleinere Tool-Liste). Reine Sicht: die effektiven Tools bleiben `Scope ∩ View`; Auth/Berechtigung sind identisch zu `/mcp`. Default `false`. **Seit #216 ist das der ANLAGE-Default:** der Schalter lässt sich nachträglich in der Admin-GUI bzw. über `PUT /api/admin/integrations/{name}/endpoint-view` umstellen (wirkt ohne Neustart und überstimmt diesen Wert in beide Richtungen). |
| `base_name` | nein | Name der Katalog-Vorlage, aus der diese Spec zuletzt per `jnpt connector upgrade` fortgeschrieben wurde — **nur bei einer DATEI-Integration** relevant, die Datei-Entsprechung der DB-Provenienz-Spalte gleichen Namens (siehe (Produkt-Doku, nicht öffentlich)). Rein informativ: Kein Verhalten der Runtime hängt daran, nur der nächste `connector upgrade`-Lauf nutzt es, um die Vorlage ohne erneutes `--vorlage` wiederzufinden. Wird nie von Hand gesetzt. |
| `tools` | ja | Liste der angebotenen Tools (mindestens eins). |

### Deklarierte Instanzwerte (`instance`)

Stufe 1 „Sicher verbinden“: gebaut, live nicht belegt. Die Vorlage deklariert
Anlagenwerte; `example` ist nur ein Hinweis und wird niemals eingesetzt.

```yaml
instance:
  - name: database
    label: Datenbankname
    kind: text
    example: mycompany
    value: meine-db # nur in der Instanz; fehlt in der Vorlage
headers:
  X-Odoo-Database: "{{instance.database}}"
```

`name` entspricht `[a-z][a-z0-9_]*` und ist eindeutig, `label` ist Pflicht.
Jede Marke muss deklariert und jede Deklaration benutzt sein. Marken dürfen
nur in Headerwerten (Spec und Tool) sowie `request.path` stehen, niemals in
`base_url`, Query, Body oder `auth`. Der Loader ersetzt sie durch Literale;
Runtime, Werkzeugfläche und Audit benötigen keine Vorlagensprache.

| Art | Wert und erlaubte Stelle |
|---|---|
| `text` | 1–256 sichtbare ASCII-Zeichen (0x20–0x7E), nur in Headern; keine Steuerzeichen |
| `segment` | 1–200 Zeichen aus `[A-Za-z0-9._~,-]`, weder `.` noch `..`, nur als ganzes Pfadsegment; kein `/`, `?`, `#` oder `%` |
| `guid` | genau eine UUID außer Null-GUID; im Pfad auch eingebettet, etwa `/companies({{instance.company_id}})`; auch in Headern |

`host` und `value` gehören derselben Artenliste `InstanceKind` an, bleiben aber
auf die festen P1-Felder beschränkt. Ein Wert gleich `example`, `mycompany`,
`CHANGE-ME` oder mit Null-GUID ist ein Ladefehler mit Label und Name.
Fehlende `value` sind nur im expliziten Vorlagenmodus von `Load` erlaubt;
Katalog und Patch verwenden denselben Loader mit `TemplateMode`.

Marken in `Host`, `Authorization`, `Proxy-Authorization`, `Cookie`,
`Content-Length`, `Transfer-Encoding`, `Connection`, `X-Forwarded-*` und
`Forwarded` sind unabhängig von Groß-/Kleinschreibung verboten. Die bestehende
Header-Sperre (einschließlich `Content-Type`) gilt zusätzlich.

`connector.InstanceFields` liefert zuerst `base_url`, dann bei OAuth2
`auth.token_url`/`auth.client_id`, dann die deklarierten Werte in Vorlagenreihenfolge.
Jedes Feld hat `Name`, `Label`, `Kind`, `Example`, `Required`; `Field` bleibt
als P1-kompatibler Feldpfad erhalten (`instance.<name>` bei Deklarationen).
Deklarierte Werte sind immer Pflicht. Der Session-Login-Body bleibt ein separater
Anhebungs-Teilbaum. Aktivierung und Anhebung nehmen `instance: {name: value}`
in der Verwaltungs-API an. Die Werte setzen Menschen über GUI, REST und CLI; der
Admin-MCP nimmt sie nur hinter dem menschlich gesetzten Schalter `target_address` an
(mit Audit und Betreiber-Mail), über `/mcp` nie. Die Verwaltungsoberfläche fragt die Werte bei Anlage und Vorlagen-Update
als Felder mit Label und Muster ab und sendet sie im `instance`-Objekt.
Die Browser-Prüfung spiegelt die Server-Regeln; `minor` ist beim Update sichtbar,
fehlende Werte sperren den Knopf. Keine Secrets und keine Erweiterung für JTL.

Ein neuer Header-Instanzwert verlangt mindestens MINOR. Ein Literal-zu-Marke-
Umstieg im Pfad verlangt MAJOR; der Flächen-Wächter prüft auch die ursprünglichen
Marken nach der Auflösung. Einzelheiten: Katalog und Anhebung (Produkt-Doku, nicht öffentlich).

### Warum `version` Pflicht ist

Eine Spec ohne Fassung lässt sich nicht **ausliefern**. Genau das ist seit
Epic #424 die Aufgabe der Connector-Bibliothek: Die mitgelieferten Vorlagen
stehen als **Katalog** im Image (siehe
Katalog & Anhebung (Produkt-Doku, nicht öffentlich)), eine Integration merkt
sich, **auf welcher Fassung sie basiert**, und ein Update — per neuem Image
oder später per signiertem Bundle (#123) — muss beantworten können: *ist das
neuer als das, worauf die laufende Instanz beruht, und was ändert sich dabei?*

Die Antwort hängt an zwei Konventionen, die `version` erst möglich macht:

- **PATCH/MINOR** (`1.0.0` → `1.0.1`, `1.1.0`) = ein **Fix ohne Änderung der
  Werkzeug-Fläche**: bessere Beschreibungen, ein korrigiertes
  `response`-Mapping, ein zusätzlicher statischer Header, ein anderes `timeout`.
- **MINOR mindestens:** eine neue `instance[]`-Deklaration für Header; ein Pfadumstieg auf Instanzmarken bleibt MAJOR.
- **MINOR mindestens:** Setzen, Ändern oder Entfernen von `response_error` / `response_error_message`: Das Fehlerverhalten ändert sich, die Fläche nicht.
- **MAJOR** (`1.x.y` → `2.0.0`) = die **Werkzeug-Fläche ändert sich**: ein Tool
  kommt hinzu/fällt weg/wird umbenannt, ein Parameter oder sein Typ ändert sich,
  ein Tool wird schreibend, eine Privacy-Deklaration wird kleiner, `base_url`
  oder `auth` zeigen woandershin.

Damit das eine **Mechanik** und nicht nur eine Bitte ist, prüft der
**Flächen-Wächter** bei jeder Anhebung die Aussage gegen die Wirklichkeit: Eine
`PATCH`/`MINOR`-Erhöhung, die die Fläche verändert, wird **fail-closed
abgewiesen** (siehe Katalog & Anhebung (Produkt-Doku, nicht öffentlich)).

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
> YAML** — siehe Update-Runbook §1a (Produkt-Doku, nicht öffentlich).

### `auth`

| Feld | Pflicht | Bedeutung |
|---|---|---|
| `header` | ja | Name des HTTP-Headers, meist `Authorization`. |
| `template` | ja | Wert des Headers mit dem Platzhalter `{{credential}}`, z. B. `"Bearer {{credential}}"` oder `"{{credential}}"`. |
| `credential` | ja (außer bei den delegierten Typen) | **Name** des Secrets im Vault — nie das Secret selbst. Anlegen mit `jnpt credential set --name <name>` (siehe README). Bei `oauth2_on_behalf_of` und `oauth2_token_exchange` **verboten**. |
| `type` | nein | Herkunft des Werts, der `{{credential}}` füllt. Weglassen = statisches Vault-Credential (Default, unverändertes Verhalten). `oauth2_client_credentials` = JanuaPort holt sich einen Access-Token selbst (siehe [App-only-Token](#app-only-token-authtype-oauth2_client_credentials)). `session_login` = JanuaPort meldet sich mit dem Passwort aus dem Vault an und nutzt die Sitzung (siehe [Session-Login](#session-login-authtype-session_login)). `oauth2_on_behalf_of` und `oauth2_token_exchange` = delegierte Identität: das SSO-Token der angemeldeten Person wird getauscht (siehe [Token-Tausch](#token-tausch-nach-rfc-8693-authtype-oauth2_token_exchange)). |
| `audience` | nur bei `oauth2_token_exchange` | Die Ziel-Audience des Tauschs, **genau ein** Bezeichner ohne Leer- und Steuerzeichen (meist die Client-ID des Zielsystems beim Identitätsanbieter). Bei jedem anderen `type` ein Ladefehler. |

Das Secret steht **niemals** in der Spec: Die Datei darf bedenkenlos eingecheckt
werden. JanuaPort setzt das Secret erst beim Aufruf in den Header ein und schreibt es
in kein Log und keine Fehlermeldung.

## Token-Tausch nach RFC 8693 (`auth.type: oauth2_token_exchange`)

Die herstellerneutrale delegierte Identität (**im Bau**: Code gebaut,
Live-Beleg folgt): JanuaPort tauscht das SSO-Token der angemeldeten Person beim
Identitätsanbieter (Keycloak, Okta, Authentik, Zitadel) gegen ein Token mit der
Audience des Zielsystems. Das Zielsystem sieht die Person, nie ihr
Anmelde-Token.

```yaml
auth:
  type: oauth2_token_exchange
  header: Authorization
  template: "Bearer {{credential}}"
  audience: ziel-api # Pflicht, genau ein Bezeichner
  scopes: [ziel:lesen] # Pflicht, wird genau so gesendet
```

- **Pflicht:** `audience`, `scopes` (mindestens einer, keiner leer).
- **Verboten:** `credential`, `token_url`, `client_id`, `session`. Token-Endpunkt
  (Discovery des SSO-Issuers), Client-ID und Secret (`sso-obo`) gehören der
  Plattform, nie der Spec.
- Nur Integrationen im Besitz `corp`; eine eigene Team-Spec darf den Typ nicht
  nutzen.
- Einrichtung, Allowlist der Login-Clients (`JNPT_SSO_EXCHANGE_ALLOWED_AZP`),
  Grund-Codes `tx_*` und Herstellerlage: §5o (Produkt-Doku, nicht öffentlich).

## App-only-Token (`auth.type: oauth2_client_credentials`)

Moderne B2B-APIs (Microsoft Graph, viele SaaS-Anbieter) akzeptieren keinen
statischen API-Key mehr, sondern verlangen einen **kurzlebigen Access-Token**.
Für unbeaufsichtigte Prozesse gibt es dafür den **Client-Credentials-Grant**:
die Anwendung weist sich selbst aus, ohne dass ein Mensch etwas bestätigt.

Setzt eine Spec `auth.type: oauth2_client_credentials`, holt JanuaPort den Token
**selbst** beim Token-Endpoint, hält ihn im Speicher und erneuert ihn rechtzeitig
vor Ablauf. Für den Rest der Spec ändert sich **nichts** — der Token wird über
dasselbe `template` in denselben `header` gesetzt wie ein statisches Credential.
Die Credentials-Seite der Admin-GUI zeigt am genannten Credential deshalb
„Client-Secret (OAuth2)“, ohne `auth.type` „API-Schlüssel“ — abgeleitet
aus der Spec; der Vault-Eintrag selbst bleibt ein untypisierter Wert.

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
> stehen in (Produkt-Doku, nicht öffentlich).
> **Heute** gilt dasselbe für die Null-GUID in `base_url` und in jedem
> Werkzeug-Pfad — bei **jeder** Spec, nicht nur bei OAuth2 (Business Central
> trägt dort Mandant und Firma). Die Meldung nennt die Stelle, bei einem Pfad
> auch das Werkzeug.
> **Heute** liest dieser Wächter die Aktivierungsfelder aus
> `connector.InstanceFields`: Auch reservierte Platzhalter-Hosts werden
> abgewiesen. In der GUI ergänzen Sie bei `guid` nur die GUID (Adresse bleibt
> aus dem Muster), bei `host` die eigene Adresse; siehe Katalog-Auslieferung §2.

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

## Session-Login (`auth.type: session_login`)

Manche Bestandssysteme kennen weder API-Key noch OAuth, sondern eine
**Anmeldung**: Benutzer und Passwort gehen per POST an einen Login-Endpunkt,
zurück kommt eine **Sitzung** — als Cookie (SAP Business One Service Layer:
`B1SESSION`, dazu `ROUTEID`) oder als Token in der JSON-Antwort (plentyONE:
`access_token`). Setzt eine Spec `auth.type: session_login`, meldet sich
JanuaPort selbst an, hält die Sitzung im Speicher und setzt sie über dasselbe
`template` in denselben `header` wie jedes andere Credential.

```yaml
# SAP Business One (Cookie-Variante)
base_url: https://b1.kunde.example:50000/b1s/v2 # https ist Pflicht
auth:
  type: session_login
  credential: sap-b1-passwort # Vault-Name des PASSWORTS (nur das Passwort)
  header: Cookie
  template: "{{credential}}"
  session:
    login_path: /Login # relativ zu base_url, feste Konstante
    login_body: # Instanzwerte dieser Anlage
      CompanyDB: "SBODEMOUS"
      UserName: "januaport-svc"
      Password: "{{credential}}" # genau EIN Blatt
    token:
      cookie: B1SESSION
      extra_cookies: [ROUTEID]
    lifetime: {field: SessionTimeout, unit: minutes, idle: true}
```

```yaml
# plentyONE (Token-Variante)
auth:
  type: session_login
  credential: plenty-passwort
  header: Authorization
  template: "Bearer {{credential}}"
  session:
    login_path: /rest/login
    login_body: { username: "api-svc", password: "{{credential}}" }
    token: { json_field: access_token }
    lifetime: { field: expires_in, unit: seconds, idle: false }
```

| Feld | Pflicht | Bedeutung |
|---|---|---|
| `credential` | ja | Benennt das **Passwort** im Vault (`jnpt credential set --name sap-b1-passwort`). Ein Credential-Override greift wie gewohnt. |
| `session.login_path` | ja | Pfad der Anmeldung relativ zu `base_url`, beginnt mit `/`. **Ohne** Platzhalter, Query, Fragment, Leerzeichen und `//` — das Passwort geht nur an `base_url`. |
| `session.login_body` | ja | Der Login-Body als Struktur (wie `body_json`). **Genau ein** Blatt ist `"{{credential}}"`; kein `{param}` (Werkzeug-Argumente erreichen die Anmeldung nie); ein Schlüssel, der nach Geheimnis klingt (`password`, `secret`, `token`, `api_key`, `kennwort` …), darf keine Konstante tragen. Mandant und Benutzer sind **Instanzwerte**, keine Geheimnisse. |
| `session.token.cookie` | eine Variante | Name des Sitzungs-Cookies (RFC 6265). Verlangt `header: Cookie` und `template: "{{credential}}"`. `extra_cookies` nimmt weitere Cookies mit, wenn das Zielsystem sie setzt. |
| `session.token.json_field` | eine Variante | Schlüssel der obersten Ebene der Login-Antwort, der den Token trägt. `header` ist dann nicht `Cookie`. |
| `session.lifetime` | nein | Feld der Login-Antwort mit der Lebensdauer, `unit: seconds\|minutes`, `idle: true` = Frist ab dem letzten Gebrauch. Ohne den Block gilt die Sitzung, bis das Zielsystem sie mit 401 ablehnt. |

Ein `session`-Block ohne `type: session_login` ist ein Ladefehler, ebenso
`token_url`/`client_id`/`scopes` bei diesem Typ.

**Was JanuaPort dabei zusichert:**

- **Das Passwort liegt nur im Vault** und verlässt den Prozess nur im
  Login-Request (gezählte Reveal-Stelle, (Produkt-Doku, nicht öffentlich) §3.5). Die
  **Sitzung lebt nur im Speicher**, nie im Log, Audit oder in einer Antwort;
  spiegelt das Zielsystem sie (oder nur einen Teil des Cookie-Kopfes) zurück,
  wird sie maskiert.
- **Fehler ohne Body:** Eine gescheiterte Anmeldung nennt Status und
  Handlungshinweis, nie die Login-Antwort. Es gibt eine WARN-Zeile, kein
  eigenes Audit-Ereignis — der fehlschlagende Aufruf trägt den Grund.
- **Eine Sitzung je Integration**, auch bei vielen parallelen Aufrufen genau
  eine Anmeldung. Proaktive Erneuerung vor dem Ablauf, sonst nach einem 401.
- **Nach einem 401 genau eine Erneuerung:** Ein lesendes Werkzeug meldet sich
  neu an und wiederholt den Aufruf einmal (ein lesender POST mit demselben
  Body). Ein **Schreib-Werkzeug** (`write: true`) meldet sich neu an,
  **wiederholt aber nicht** und antwortet „Die Sitzung … ist erneuert — der
  Schreibvorgang wurde nicht wiederholt; das Werkzeug bitte erneut aufrufen".
  Lehnt das Zielsystem auch die neue Sitzung ab, endet der Aufruf mit dem
  gewohnten 401-Fehler.
- **Schutz des Dienstkontos vor Sperre:** Lehnt die Anmeldung das Passwort ab
  (400/401/403), meldet sich JanuaPort **nicht wieder an, bis das Credential
  ersetzt ist** — jeder Aufruf sagt bis dahin „Anmeldung am Zielsystem pausiert
  nach Fehlschlag". Netz- und Serverfehler pausieren 60 s. Erfolgreiche
  Anmeldungen höchstens eine je 10 s.
- **Wird das Passwort ersetzt** (neue Version im Vault), meldet sich
  JanuaPort vor dem nächsten Aufruf neu an — ohne Umweg über ein 401.

**Bewusste Grenzen (v1):**

- **https ist Pflicht, auch im LAN.** Über diese Verbindung geht das Passwort;
  einen `http`-Weg gibt es nicht. Viele SAP-B1-Service-Layer laufen mit einem
  **selbstsignierten Zertifikat** — die sind **ohne eigene vertrauenswürdige CA nicht
  nutzbar**. Die Zertifikatsprüfung abzuschalten ist kein Ausweg und im Code
  per Wächter ausgeschlossen.
- **Kein Logout:** Bei jedem Neuaufbau der Werkzeuge (SIGHUP, jede Anlage zur
  Laufzeit) entsteht eine neue Sitzung; die alte endet beim Zielsystem nach
  Leerlauf. Je Neuaufbau bleibt also **bis zu eine verwaiste Sitzung** stehen.
- **Je Prozess eine Sitzung:** Bei Postgres active/active hält jede Instanz
  ihre eigene. Bei SAP heißt das je Instanz eine belegte Sitzung; ob das die
  Lizenz belegt, misst die Live-DoD.
- **Nur JSON-Login.** Kein Formular-Login, kein zweites Geheimnis, kein
  OAuth2 Password Grant (geplante Erweiterung; Produkt-Doku, nicht öffentlich).
- **Kein Feld in der Anlage-Oberfläche:** `login_body` wird über die YAML bzw.
  `jnpt connector add` gepflegt. Eine Katalog-Vorlage trägt Platzhalter, die
  vor der Aktivierung ersetzt werden müssen (Null-GUID, wie bei OAuth2).
- **Team-Integrationen** nutzen den gehärteten Client (nur öffentliche
  Ziele) — ein Service Layer im LAN geht nur im Besitz `corp`.

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

- **Feste Werte oder deklarierte Instanzmarken.** `{{instance.<name>}}` wird
  beim Laden aufgelöst. `{param}` und `{{credential}}` bleiben verboten.
- ⚠️ **Ein Header trägt nie ein Secret.** Zugangsdaten gehen ausschließlich über
  `auth` — ein Weg, ein Vault-Zugriff, eine Stelle, an der redigiert wird. Wer
  einen API-Key als Header braucht, setzt ihn über `auth.header` +
  `auth.template` (genau dafür ist er da).
- **Diese fünf Header gehören JanuaPort** und werden hier **abgewiesen** (mit einer
  Meldung, die sagt, wem sie gehören):

  | Header | Kommt von |
  |---|---|
  | `Authorization` | `auth.header` / `auth.template` (Credential aus dem Vault) |
  | `Content-Type` | `request.encoding` |
  | `Content-Length` | setzt Go selbst aus dem Body |
  | `Host` | ergibt sich aus `base_url` |
  | `X-Jnpt-Freigabe` | setzt ausschließlich das Freigabe-Gate nach atomarer Reservierung (siehe „Freigabepflicht“) |

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
Werte und allgemeine Vorlagensprache — und keine Auswertung von **Antwort**-Headern (etwas
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

- Der **Text-Block** trägt die Projektion **unverändert** als kompaktes JSON.
  Eine Liste ist dort eine Liste — daran ändert sich nichts, und bestehende
  Agenten-Prompts, die diesen Text lesen, bleiben gültig. **Einzige Ausnahme:**
  ein Werkzeug mit `text_format: toon` (siehe
  [unten](#textform-des-text-blocks-text_format)); ohne das Feld bleibt der Text
  byteweise das JSON.
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

### Textform des Text-Blocks (`text_format`)

Stufe 1 „Sicher verbinden“, gebaut, unveröffentlicht. Lange, gleichförmige
Listen kosten als JSON viele Tokens, weil jeder Schlüssel in jeder Zeile steht.
Ein Werkzeug kann seinen **Text-Block** deshalb als
[TOON](https://github.com/toon-format/spec) ausgeben:

```yaml
- name: list_customers
  description: Lists customers.
  request: { method: GET, path: /v1/customers }
  response: items
  text_format: toon      # json (Standard) | toon
```

```text
[3]{id,name,city}:
  1,‹kunde-6b8430›,"Köln, Süd"
  2,‹kunde-6e883a›,Bonn
  3,‹kunde-937ad4›,Essen
```

**Wann es greift.** Nur bei einem Werkzeug mit `text_format: toon`, und nur wenn
die Antwort eine Tabelle ist: ein Array (an der Wurzel oder als direkter Wert des
Wurzelobjekts) aus **mindestens 5 Objekten** mit **derselben Schlüsselmenge** und
**nur primitiven Werten** — und nur, wenn der TOON-Text kürzer ist als das JSON.
Alles andere (4 Zeilen, uneinheitliche Schlüssel, verschachtelte Werte,
gemischte Arrays, Steuerzeichen, ungültiges UTF-8) bleibt **byteweise das
bisherige JSON**. Ein Geschwisterobjekt neben der Tabelle wird mitgeschrieben.

**Was es nicht ändert.** TOON ist der **letzte** Schritt: Projektion,
Pseudonymisierung und Datenfilter laufen vorher, das Audit (`ReportResponse`) ist
weiter JSON, ebenso `structuredContent`, die Freigabe und die Admin-API. Ein
pseudonymisiertes Kürzel `‹label-id›` steht im TOON-Text byteweise genauso wie
dort; ein Klartext kommt nie hinzu. Werte mit Komma, Doppelpunkt,
Anführungszeichen, Zeilenumbruch, führendem `-` oder `#`, Leerraum am Rand, leere
und zahlen- oder wahrheitswertartige Strings stehen in Anführungszeichen — ein
Wert aus dem Zielsystem kann so keine zusätzliche Zeile oder Spalte erzeugen.

**Beschreibung.** Bei `toon` hängt das Gateway einen festen Satz an die
Beschreibung des Werkzeugs (`toon.FormatHint`), damit der Agent die Tabelle lesen
kann; ohne das Feld bleibt die Beschreibung unverändert.

**Grenzen.** Kein Schalter je Anlage oder Token, nur das Feld je Werkzeug. Nur
REST- und Datenbank-Werkzeuge; Upstream-MCP, Dateien, Karteien, `memory` und
`wissen` bleiben unberührt. Listenform (`- `), Key-Folding und andere Trennzeichen
als das Komma gibt es nicht. Ein Wechsel von `text_format` ist eine andere
Antwortform für die KI und damit **MAJOR** (Flächen-Wächter). Katalog-Vorlagen
setzen das Feld nicht; das geschieht je Vorlage als eigene MAJOR-Anhebung.

### Leere Antwort: „ausgeführt, keine Daten"

Antwortet das Zielsystem mit **2xx und leerem Body** (nach dem Trimmen), ist das
ein Erfolg: Das Ergebnis ist `{"status": <HTTP-Status>}`, zum Beispiel
`{"status": 202}` bei Graph `sendMail` oder `{"status": 204}` bei einem Schreib-
Endpunkt ohne Rückgabe. Ein `response`-Ausdruck und ein `response_error`-Ausdruck
werden dann nicht angewendet, der Audit-Status ist `ok`. Für die KI heißt das: **ausgeführt, keine Daten — ein
Wiederholungsaufruf ist nicht nötig** (bei einem Schreibwerkzeug würde er die
Aktion doppelt auslösen). Ein leerer Body bei 4xx/5xx bleibt ein Fehler mit
Status, und ein nicht leerer Body, der kein gültiges JSON ist, bleibt ein Fehler.
Schreibwerkzeuge mit leerer Erfolgsantwort sagen den `{"status": …}`-Fall in ihrem
Werkzeugtext.

### Fehler im 2xx-Body: `response_error`

Manche Zielsysteme melden einen Fehler **nicht** mit einem 4xx/5xx, sondern mit
HTTP 200 und einem Fehlerzeichen im JSON (`{"ok": false, "error": "channel_not_found"}`
bei Slack, ähnlich bei einigen RPC-APIs). Ohne weitere Angabe gilt jedes 2xx mit
gültigem JSON als Erfolg — die KI hielte so eine nicht zugestellte Nachricht für
verschickt. Ein Werkzeug erklärt das Kennzeichen deshalb selbst:

```yaml
  - name: post_message
    write: true
    # ...
    response: "{ts: ts}"
    response_error: "ok == `false`"      # JMESPath auf dem 2xx-JSON
    response_error_message: error        # JMESPath auf den Meldungstext (optional)
```

| Feld | Bedeutung |
|---|---|
| `response_error` | JMESPath auf dem 2xx-JSON. Ergibt der Ausdruck **genau `true`**, ist der Aufruf ein Fehler. Jedes andere Ergebnis — `false`, `null`, ein String, eine Zahl, ein Array, ein nicht leeres Objekt — ist ein Erfolg wie ohne das Feld. Ein „wahr aussehender" Wert zählt also nicht: Der Ausdruck muss selbst einen Vergleich bilden (`ok == `false``, `error != `null``). |
| `response_error_message` | JMESPath auf den Meldungstext, höchstens **200 Zeichen**. Nur ein **String** wird ausgegeben; ein Objekt, Array, eine Zahl oder `null` ergibt keine Meldung. Nur zusammen mit `response_error` erlaubt (sonst Ladefehler). |

**Regeln beim Laden:** Ein ungültiger JMESPath-Ausdruck in einem der beiden
Felder weist die Spec ab (nicht erst der Aufruf). `response_error_message` ohne
`response_error` und `response_error` neben `response_file` (eine Datei ist kein
JSON) sind Ladefehler. Beides ist an jedem Werkzeug erlaubt, lesend wie schreibend.

**Was bei `true` passiert:** Der Aufruf endet als `upstream_error` — **derselbe
Weg wie ein 4xx/5xx**: Werkzeugfehler für die KI, Audit-Status `upstream_error`
(es gibt keinen neuen Status), Tagesdeckel (`daily_cap`) und Metriken zählen ihn
wie einen Upstream-Fehler. Die Meldung lautet „Zielsystem meldet trotz HTTP 200
einen Fehler (response_error)" und trägt höchstens den gedeckelten Text aus
`response_error_message` (ein vom Zielsystem gespiegeltes Credential ist geschwärzt,
Steuerzeichen fallen weg); **nie den Body und nie die `response`-Projektion**.
Das Kennzeichen wird auf dem Dokument vor der Projektion geprüft.

**Grenzen (bewusst klein):**

- Ein **leerer** 2xx-Body wertet das Kennzeichen nicht aus: Das Ergebnis
  bleibt `{"status": <Code>}`.
- Ein Ausdruck, der auf dem Dokument nicht auswertbar ist (etwa `abs()` auf einem
  String), ist ein `config_error` — laut statt still Erfolg. Die Meldung nennt den
  Ausdruck, nicht den Body.
- Keine Wiederholung und kein Alarm: Das Kennzeichen macht den Fehler sichtbar, es
  ändert nichts am Einzelversuch (Schreibwerkzeuge werden nie wiederholt).
- Der 4xx/5xx-Weg bleibt unverändert; das Kennzeichen gilt nur für 2xx.
- Der Selbsttest läuft durch denselben Pfad: Ein Probe-Werkzeug mit
  `response_error` meldet bei `true` `upstream_error`.

**Versionsfolge:** Setzen, Ändern oder Entfernen von `response_error` oder
`response_error_message` ändert das Fehlerverhalten, aber nicht die Werkzeug-Fläche.
Der Flächen-Wächter (`DimResponseError`) stuft es deshalb als **MINOR** ein: Eine
PATCH-Erhöhung wird abgewiesen, MINOR genügt, MAJOR bleibt für Änderungen der
Fläche.


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
| `hinweis` | fester Injection-Rahmensatz, ergänzt um inhaltsfreie Fundstellen versteckter Abschnitte |
| `mime` | der aus den **Bytes** erkannte Typ |
| `declared_mime` | der Typ, den der Dienst **behauptet** hat |
| `bytes` | Größe der abgerufenen Datei |
| `kind` | `pdf`, `xml`, `json`, `csv`, `text`, `docx`, `xlsx`, `pptx` oder `unbekannt` |
| `readable` | ob Inhalt geliefert wird — `false` heißt: nicht raten |
| `text` | der gewonnene Inhalt |
| `truncated` | ob gekürzt wurde |
| `text_bytes_total` | Länge des Textes vor dem Zuschnitt |
| `hidden_text_count` | erkannte versteckte Abschnitte im gelesenen Teil (sonst 0); Seite/Absatz und Gründe stehen als Zusatz im festen Injection-Hinweis `hinweis` |
| `note` | die ehrliche Erklärung, wenn (nicht vollständig) gelesen werden konnte |
| `embedded[]` | in einem PDF eingebettete Dateien — bei einer E-Rechnung das XML |

PDF und DOCX markieren erkannten versteckten Text als `[versteckter Text: …]`,
ohne ihn zu entfernen oder zu sperren. Benachbarte versteckte Läufe zählen als
ein Abschnitt. Erkennung und Grenzen: [Datei-Connector](file-connector-spec.md).

Gelesen werden in dieser Version: **PDF-Textebene**, **in einem PDF eingebettete
Dateien** (ZUGFeRD/Factur-X — das XML ist für eine KI die belastbare Quelle für
Beträge und Rechnungsnummern), **XML, JSON, text/plain, text/csv** sowie
**Word, Excel, PowerPoint (docx, xlsx, pptx)**. Bilder, alte Office-Dateien,
`.eml` und sonstige ZIP kommen mit `readable: false` plus Typ und Größe zurück.
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
Schreib-Formen gibt es im Format nicht — bewusst eng: additiv
(z. B. „Beleg in die Inbox legen", „Entwurf anlegen"), nie löschen oder
überschreiben. **Eine Ausnahme von „umkehrbar" ist ausdrücklich entschieden:** Lexwares `create_invoice` legt eine Rechnung an und schließt sie
ab (`finalize=true` als Konstante, nie als Parameter). Das ist additiv, über die
API aber nicht mehr änderbar; Korrektur ist eine Gutschrift in Lexware. Die
Beschreibung sagt das, ebenso, dass ein Wiederholen eine zweite Rechnung
erzeugt (Lexware kennt keinen Idempotenz-Schlüssel). Begründung und Grenzen: (Produkt-Doku, nicht öffentlich).

```yaml
tools:
  - name: upload_voucher_file
    description: >
      Uploads a receipt FILE into the inbox. This is a WRITE action. It is
      annotated as such, so your client may ask the user; JanuaPort itself
      never asks. It needs the tool-exact permission
      "lexware-office:upload_voucher_file". The file is base64 in "content"
      (max 5 MiB decoded); provide "filename" and "content_type". Returns the
      new file id.
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
  nachfragen kann. Ohne `freigabe` gehört in die Description der einheitliche **Kernsatz**
  (heute, wörtlich, mit dem tool-genauen Scope):

  > This is a WRITE action. It is annotated as such, so your client may ask
  > the user; JanuaPort itself never asks. It needs the tool-exact permission
  > "`<integration>:<tool>`".

  Nur ein Werkzeug, das **tatsächlich** Geld bewegt oder nach außen wirkt
  (z. B. eine Mail versendet, eine Zahlung auslöst), bekommt einen zweiten
  Satz (Satz B):

  > It runs without a chat question once a human approved this process at
  > setup (use case and AI mandate); the tool-exact permission is the
  > boundary.

  Begründung: Die Freigabe geschieht einmal, wenn ein Mensch den Prozess
  aufsetzt (Use Case und KI-Mandat); eine Einzelbestätigung je Aufruf gibt es
  nicht, die Grenze ist das tool-genaue Recht.

  **Verbindlich (PO-Entscheid heute):** Satz B steht nur dort, wo das
  Werkzeug es wirklich tut. Die frühere Wenn-Formulierung („If this moves
  money or leaves the company …") ist verboten — an einem Werkzeug, das es nie
  tut, ist sie Rauschen, das die KI bremst. Einen Beleg
  ablegen, eine Datei anhängen, einen Entwurf anlegen oder eine Mail
  verschieben bewegt kein Geld und wirkt nicht nach außen. Dasselbe gilt für
  Lexwares `create_contact` und `create_invoice`: Die Rechnung wird
  angelegt und abgeschlossen, aber weder versendet noch bezahlt. In der heute
  ausgelieferten Fläche trägt den Satz deshalb genau zwei Werkzeuge:
  `linkedin-seite-community:reply` veröffentlicht eine öffentliche
  Antwort als Organisation, `microsoft-graph-mail:reply` sendet eine
  Antwort an den Absender einer vorhandenen Mail. Kommt ein weiteres
  echtes Sende- oder Zahlwerkzeug, gehört es in die Liste
  `geldOderAussenwirkung` in (Produkt-Doku, nicht öffentlich); der Pin lässt
  Satz B an jedem anderen Werkzeug scheitern (auch umformuliert), und der
  Wächter verbietet die alte Wenn-Formulierung in jedem Werkzeugtext.

  **Warum nicht „a human must confirm“ bei gewöhnlichen Writes:** Ohne deklarierte `freigabe` fragt JanuaPort nicht selbst;
  fragen kann nur der Client über die
  Annotation. Ein produktiver Agent, der „ein Mensch muss bestätigen" liest,
  wartet auf eine Bestätigung, die nie kommt. Eine Freigabe ist ein Auftrag
  des Menschen — ein Schritt in der Arbeitsliste oder eine ausdrückliche
  Anweisung —, keine Rückfrage im Chat. Der Wächter
  (Produkt-Doku, nicht öffentlich) verbietet den alten Satz in jeder Werkzeug-
  und Parameterbeschreibung und pinnt den Kernsatz an jedem Schreibwerkzeug
  der ausgelieferten Vorlagen.
- **Audit:** Der Aufruf wird als schreibend markiert (`jnpt audit list --write`).
  Scheitert das Schreiben des Audit-Events **nach** dem Upload, sieht der Agent
  einen Fehler, obwohl die Datei evtl. schon hochgeladen wurde — die Meldung
  bittet dann, im Zielsystem zu prüfen, statt blind zu wiederholen.

### Freigabepflicht (`freigabe`)

Optional: `freigabe.medien_ablage: redaktion-medien` bindet ein gültiges
Freigabe-Schreibwerkzeug an einen Ablagenamen (Namensregel der Datei-Integrationen).
Außerhalb von freigabe, an einem Lesewerkzeug, mit ungültigem Namen oder unbekannten
Schlüsseln wird die Spec abgewiesen. Die Option ändert `DimFreigabe`: Setzen,
Ändern oder Entfernen verlangt MAJOR. Zur Laufzeit sind genau eine aktive Ablage
und derselbe Besitzer wie bei der Spec erforderlich; sonst gibt der Medienweg 404.
Die SSO-Freigabeansicht liest `datei` nur aus dem Schnappschuss, prüft Status offen,
Wirkungshash und Byte-SHA-256; PNG/JPEG/GIF inline, PDF als Download. Privacy-Sperre
und 32-MiB-Deckel des vorhandenen get_file bleiben verbindlich. Kein KI-Byteweg.


Stufe 2, der Gateway-Teil ist gebaut, unveröffentlicht; menschliche Oberfläche und
Beisteller werden separat geliefert. Die Option gehört ausschließlich an `write: true`:

```yaml
    freigabe:
      vorschau: vorschau
      schluessel: [eintrag_id]
```

`vorschau` muss ein anderes, existierendes lesendes JSON-Werkzeug derselben Spec
sein. `schluessel` ist nicht leer und enthält eindeutige, erforderliche
String-Parameter beider Werkzeuge. Die Schreibparameter müssen als Menge genau
den Schlüsselfeldern entsprechen; zusätzliche optionale oder erforderliche
Schreibparameter sind Ladefehler. Das Gate weist auch zusätzliche Aufrufargumente
vor Vorschau und Start ab. Kein Mail-Feld, keine Quelle `argumente`.
Ungültige Deklarationen scheitern beim Laden. Setzen, Ändern und Entfernen
verlangen MAJOR (`DimFreigabe`); LinkedIn-Manage springt deshalb auf 2.0.0.

Der Handler holt die aktuelle Vorschau über denselben Executor und baut die
Wirkung aus dessen Feldern `aktion`, `ziel_urn`, `text`, `medien` mit sichtbarem
`name`/`sha256` und optional `umfrage` mit `frage`, geordneten `antworten` und
`dauer`. Die Felder liegen direkt im projizierten Vorschauobjekt. Das Pflichtfeld `hash`
muss beim Anfordern und erneut vor Start mit dem selbst berechneten v2-Hash
übereinstimmen; sonst Fehler ohne Anlage beziehungsweise Verbrauch. Bei LinkedIn
setzt der Server die Aktionsnamen posten/bearbeiten/loeschen/kommentar anhand
der Schreibroute, sonst den Werkzeugnamen. Nur Schlüsselfelder und diese Aktion
gehen in die Vorschau; KI-Hash und KI-Freigabestatus sind keine Autorität.

`freigabe_anfordern(werkzeug, schluessel)` verwendet `integration:werkzeug` und
ein JSON-Objekt mit genau den Schlüsselfeldern. Es verlangt
`freigabe:freigabe_anfordern` und das exakte Zielrecht samt dessen Datenfilter,
liefert ID und `pfad: /freigaben/<id>` und übernimmt den globalen Deckel von 20
offenen Aufträgen. Nur ein Mensch mit SSO und Freigeber-Merkmal entscheidet.
`freigabe_status(id)` verlangt `freigabe:freigabe_status` sowie dasselbe Zielrecht
samt Filter und liefert nur `status`, `erstellt`, `entscheidungszeit`.
Ein bloßer Provider-Scope `freigabe` gibt keine dieser Fähigkeiten frei.

Eine passende freigegebene Wirkung wird mit atomarem CAS und Audit auf laeuft
gesetzt, bevor der Schreibrequest hinausgeht. Der ausschließlich vom Server
gesetzte Header lautet exakt:

```text
X-Jnpt-Freigabe: hash=freigabe:v2:sha256:<64 kleine Hexzeichen>
```

Der Header trägt genau einen Wert und keine Auftrags-ID; die Auftragsbindung
erfolgt durch das Start-CAS im Kern. Er ist case-insensitiv auf Spec-/Werkzeugebene und in auth.header
reserviert. Parameter-zu-Header-Ziele sind kein Teil des Formats; `Load` weist
sie ab. Werkzeugargumente setzen den Header nicht.

`ausgefuehrt: true` bestätigt den Erfolg, auch zusammen mit `wiederholt: true`
für ein bereits gespeichertes Beisteller-Ergebnis desselben Hashs. Der
Wiederholmarker allein genügt nicht.
HTTP 200 mit `nicht_ausgefuehrt: true` erlaubt Wiederholung ohne neuen Klick, ausschließlich
vor dem ersten LinkedIn-Schreibversuch im Beisteller und nach bestandenem
Header-Check. Der Kern wertet Ergebnisfelder nur aus 2xx-Antworten aus;
409/429/503 bleiben auch mit einem Marker im Fehlerbody unklar. Nach Start-CAS
läuft der Schreibcall mit `context.WithoutCancel`; Client-Abbruch und Aufruferfrist
beenden ihn nicht. Die Executorfrist (höchstens 120 s) und ein kürzeres
`http.Client.Timeout` gelten weiter. Vorschau und Aufrufe ohne gestarteten Auftrag
bleiben am Client-Kontext. Executor-Timeout, 5xx, widersprüchliche Marker und
unbekannte Antworten ohne Ergebnisfelder werden unklar;
keine automatische Wiederholung. Bei fehlender Freigabe oder Hashabweichung
bleibt der Auftrag unverändert. Auditfehler vor Start verhindern das Senden;
bei Abschlussfehler bleibt laeuft gesperrt bis zur auditierten Neustart-Recovery.

Der Kernsatz für diese tatsächlich gesperrten Werkzeuge lautet:

> This is a WRITE action. JanuaPort sends it only after matching human SSO approval.
> It needs the tool-exact permission "integration:werkzeug".

### Tagesdeckel (`daily_cap`)

Ein Schreibwerkzeug kann je Tag nur begrenzt oft aufgerufen werden — ein
Sicherheitsnetz gegen einen Agenten, der in eine Schleife gerät, ohne dass ein
Mensch jeden Aufruf freigibt. Die Spec setzt den Deckel am Werkzeug:

```yaml
  - name: set_lead_stage
    write: true
    daily_cap: 50          # höchstens 50 Versuche je Integration und UTC-Tag
```

**Regeln (beim Laden geprüft):** eine ganze Zahl größer 0; nur an einem
Werkzeug mit `write: true` (an einem Lesewerkzeug oder einem lesenden POST ist
es ein Ladefehler). Er ist allgemein — jedes Schreibwerkzeug jeder Spec kann ihn
setzen, es gibt keinen Anbieter-Sonderfall im Kern. Weder ein Aufrufer noch ein
Token kann ihn ändern.

**Was gezählt wird:**

- Gezählt werden **Versuche**, und zwar sobald die Eingabe geprüft ist (Schema,
  `enum`, Typen, Body) und **vor** dem Request an das Zielsystem. Ein
  Upstream-Fehler (4xx, 5xx, 429) und ein Timeout verbrauchen den Versuch mit;
  eine Eingabe, die schon an der Prüfung scheitert (z. B. ein `enum`-Verstoß),
  zählt nicht.
- Der Zähler gilt **je Integration (Spec-Name) und je Werkzeug**, nicht je Token
  und nicht je Identität. Zwei Integrationen aus derselben Vorlage zählen
  getrennt, zwei Werkzeuge derselben Integration ebenso.
- Tageswechsel ist die UTC-Mitternacht, nicht die Ortszeit.
- **Der Zähler liegt nur im Speicher des Serverprozesses.** Er beginnt beim
  Tageswechsel und nach jedem Neustart bei null (ein Neuladen der Integrationen
  baut den Executor neu und setzt ihn ebenfalls zurück). Es gibt keinen Store
  und keinen Schreibpfad dafür.
- Prüfen und Zählen sind ein Schritt (Mutex): Parallele Aufrufe überschreiten
  den Deckel nicht.

**Was beim Erreichen passiert:** Der Aufruf endet mit einer festen Absage, bevor
ein Request entsteht. Der Text nennt weder Parameter noch Werte. Die Absage ist
ein `*runtime.DailyCapError` (Unwrap auf `*ArgumentError`), das Audit führt sie wie
jeden abgewiesenen Aufruf (Status `argument_error`, ein eigener Status ist ein
Nachschnitt in der Komposition).

**Flächen-Wächter:** Der Deckel gehört zur Werkzeug-Fläche
(`DimDailyCap`). Setzen, Ändern oder Entfernen ist `major`.


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
      WRITE action. It is annotated as such, so your client may ask the user;
      JanuaPort itself never asks. It needs the tool-exact permission
      "microsoft-graph-mail:create_draft".
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
  außer das Werkzeug ist ausdrücklich als lesender POST deklariert
  (`read_via_post: true`, siehe unten).
- `body_json` und `body` (multipart) **schließen sich aus**: ein Tool sendet
  einen Body, nicht zwei.
- Die **oberste Ebene ist ein Objekt** (`feld: wert`). Ein einzelner Text oder
  eine Liste als ganzer Body ist nicht vorgesehen.
- **Keine leere Liste** irgendwo im Baum und **kein leerer Body** — beides ist
  ein Versehen.
- **Ein leeres Objekt `{}` im Baum ist eine Konstante**: Es wird
  genau so gesendet. Auslöser ist Lexware, das beim Anlegen eines Kontakts
  `roles: {customer: {}}` verlangt („The role must be set as an empty object").
  Ein Objekt, das erst durch weggelassene Parameter leer **wird**, entfällt
  weiterhin (siehe unten).
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
- Konstante Werte aus dem YAML (`normal`, `true`, Zahlen, ein geschriebenes
  `{}`) bleiben stehen — mit einer Ausnahme:
- **Ein Objekt als Listen-Eintrag, von dessen Platzhaltern keiner gesetzt ist,
  entfällt ganz, samt seiner Konstanten**. Beispiel Lexware
  `create_invoice`: Die zweite Rechnungsposition trägt `type: custom` und
  `currency: EUR` als Konstanten. Ohne alle `item2_*`-Parameter verschwindet die
  ganze Position, die Liste wird kürzer. Ist nur ein **Teil** gesetzt und trägt
  der Eintrag Konstanten, lehnt JanuaPort den Aufruf **vor dem Senden** ab
  (`ArgumentError`): Die Meldung nennt die fehlenden
  Parameternamen („Listeneintrag unvollständig: item2_net_price,
  item2_tax_rate fehlen"), es geht nichts ans Zielsystem. Still weggelassen wird
  ein teilweise gesetzter Eintrag nie: Bei einer Rechnungsposition wäre das ein
  Fehlbetrag. Gezählt werden alle Platzhalter im Teilbaum des Eintrags, auch
  verschachtelte (`unitPrice.netAmount`); ein Typfehler zählt als gesetzt. Ein
  Eintrag **ohne** Konstanten (Odoo `vals_list`) geht auch teilweise gesetzt
  hinaus. Ein Listen-Objekt ganz ohne Platzhalter (nur Konstanten) bleibt immer.
- **Tupel entfallen ganz.** Eine Liste aus einfachen Werten mit mindestens
  einem festen Wert, die **selbst Eintrag einer Liste** ist — etwa ein
  Filter-Tripel `["name", "ilike", "{q}"]` in einer Liste von Filtern —, entfällt
  als Ganzes, sobald einer ihrer Werte entfällt. Aus `["name", "ilike"]` würde
  sonst ein kaputter Filter.
- **Als Wert eines Feldes gilt Eintrag für Eintrag.** `fields: ["name",
  "email", "{extra_field}"]` wird ohne `extra_field` zu `["name", "email"]` —
  entfiele die ganze Liste, lieferte eine API wie Odoo still **alle** Felder.

### Grenzen (v1)

- **Typtreue nur beim reinen Platzhalter.** `"{page}"` mit einem
  `integer`-Parameter landet als Zahl `7` im JSON, mit einem
  `boolean`-Parameter als `true`/`false` (heute). Eine gemischte Vorlage
  (`"Seite {page}"`) und jeder `string`-Parameter bleiben Text.
- **Verschachtelte Oder-Filter.** Bei einer Präfix-Domäne wie
  `["|", ["name", "ilike", "{q}"], ["email", "ilike", "{email}"]]` entfällt ohne
  `email` nur das zweite Tripel; `["|", […]]` bleibt stehen. Optionale Filter
  deshalb nur in UND-Verknüpfungen verwenden.
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

## Lesender POST (`read_via_post`)

Manche APIs verlangen **jeden** Aufruf als `POST` mit JSON-Body — auch reines
Lesen: Odoo ab Version 19 (JSON-2-API), GraphQL, Elasticsearch `_search`,
Jira-Suche. Ohne Deklaration wäre ein solches Werkzeug ein Schreibwerkzeug
(tool-genaues Schreibrecht, Schreib-Annotation und Schreib-Audit). Mit
`read_via_post: true` erklärst du den Aufruf ausdrücklich zum **Lesevorgang**:

```yaml
  - name: search_partners
    description: Searches customers by name. Read-only.
    params:
      - name: q
        description: Optional part of the name.
        type: string
      - name: extra_field
        description: Optional additional field to return.
        type: string
        enum: [phone, street] # in einer Feldliste Pflicht (siehe Regeln)
      - name: active
        description: Only active (true) or archived (false) customers.
        type: boolean
      - name: order
        description: Sort order.
        type: string
        enum: [name asc, id desc]
    request:
      method: POST
      path: /json/2/res.partner/search_read # konstant: die Methode steht im Pfad
      encoding: json
      read_via_post: true
      body_json:
        domain:
          - ["name", "ilike", "{q}"] # Tupel: entfällt ohne q ganz
          - ["active", "=", "{active}"] # typtreu: true/false
        fields: ["name", "email", "{extra_field}"]
        limit: 80 # fester Deckel
        order: "{order}" # enum: nur die zwei Werte
```

Das Werkzeug ist dann in jeder Hinsicht ein Lese-Werkzeug: `readOnlyHint: true`,
ein Leserecht genügt (auch ein Recht auf die ganze Integration), keine
Bestätigung, im Audit-Log kein Schreibvorgang.

**Regeln (beim Start geprüft):**

- `read_via_post: true` verlangt `method: POST`, `encoding: json` mit
  `body_json` und **kein** `write: true`. Ein `POST` **ohne** die Deklaration
  bleibt an `write: true` gebunden — ein vergessenes `write` fällt weiter auf.
- **Der Pfad ist konstant** — kein `{param}` darin. Bei diesen APIs steht die
  Operation im Pfad; ein Platzhalter (`/json/2/{model}/{method}`) ließe den
  Aufrufer `unlink` statt `search_read` schicken.
- **Kein Body-Wert besteht nur aus einem freien Text-Parameter** (`string` ohne
  `enum`). `query: "{q}"` gegen GraphQL ließe den Aufrufer eine `mutation`
  schicken. Erlaubt sind Parameter mit `enum`, Zahlen, Wahrheitswerte, eine
  Vorlage mit festem Text (`"Kunde {q}"`) und ein Eintrag in einem
  Filter-Tripel, das selbst in einer Liste steht (`domain: [["name", "ilike",
  "{q}"]]`). Eine einfache Liste als Feldwert zählt NICHT dazu — in
  `args: ["db", 2, "res.partner", "{q}"]` wählt die feste Position bei JSON-RPC
  die Methode. Deshalb braucht auch ein optionaler Eintrag in `fields` einen
  Parameter mit `enum`.
- **Dasselbe gilt für `query`-Werte:** `value: "{q}"` mit einem freien
  Text-Parameter wird abgelehnt; `value: "search_{q}"`, Zahlen, Wahrheitswerte
  und `enum`-Parameter sind erlaubt.
- `response_file` bleibt bei jedem `POST` verboten.

> **Deine Aussage, nicht unsere Prüfung.** Die Regeln oben schließen die
> bekannten Wege, auf denen ein Aufrufer die Operation wählen könnte — sie
> garantieren nicht, dass es keinen weiteren gibt. JanuaPort kann nicht
> nachprüfen, ob die Methode beim Anbieter wirklich nichts ändert. `read_via_post: true` ist
> deine Erklärung dazu — prüfe sie gegen die Anbieter-Doku (bei Odoo: `search_read`,
> `read`, `search_count`, `fields_get`, `name_search` lesen; `create`, `write`,
> `unlink`, `action_*` schreiben). Mitgelieferte Specs sind zusätzlich im Test
> `TestLesendePostsSindBelegt` mit Pfad und Doku-Verweis festgehalten.

> **Pseudonyme in Suchwerten.** Wie bei jedem Lese-Werkzeug werden Pseudonyme in
> Text-Parametern vor dem Aufruf zurückgewandelt — eine Suche nach einem
> pseudonymisierten Namen findet den echten Datensatz. Das ist gewollt, keine
> Lücke.

Für `jnpt connector check` gilt: Ohne `check: true` nimmt die Probe ein
`GET`-Werkzeug vor einem lesenden POST. Soll ein lesender POST die Probe sein
(Odoo: `res.users/context_get`), markiere ihn mit `check: true`.

## Audit & Redaction (`redact_params`)

Werkzeug-Aufrufe werden protokolliert (`jnpt audit list`, siehe README).
Out-of-scope-/unbekannte Namen auf `/mcp` und seinen Sichten erzeugen
`denied` ohne Argumente; ab 30 Einzelereignissen je Token/Minute werden
weitere Versuche als Zähler zusammengefasst (unveröffentlicht). Das Audit-Event speichert die **Tool-Argumente** als JSON — nie Header
oder das Credential. Sind einzelne Argumente trotzdem sensibel (z. B. eine Personen-ID
oder ein Suchbegriff mit PII), nimm ihre Namen in `redact_params` auf:

```yaml
redact_params: [from, customer_id]
```

Die gelisteten Parameter erscheinen im Audit-Log dann als `"[REDACTED]"`. Die
Liste gilt **connector-weit**: Ein Name wird in jedem Tool dieses Connectors
redigiert, das ihn als Parameter hat.

> ⚠️ **Das gilt auf der Protokolltiefe „Metadaten" (dem Default) — nicht darüber
>.** Der Betreiber kann die Protokolltiefe auf „Abfragen" oder „Antworten"
> stellen (eine bewusste, auditierte Entscheidung; Datenschutz-Einordnung in
> (Produkt-Doku, nicht öffentlich)). Dann stehen die VOLLSTÄNDIGEN Argumente —
> auch die `redact_params`-Felder — im Inhalt des Protokolls (eine Nebentabelle
> des Audit-Logs, nur für Menschen in der Verwaltung lesbar, jeder Abruf selbst
> protokolliert, mit eigener Inhaltsfrist). `redact_params` beschreibt PII, kein
> Geheimnis: Ein Spec-Autor darf sich nicht darauf verlassen, dass der Wert den
> Prozess nie verlässt. Geheimnisse gehören nie in einen Parameter, sondern ins
> Credential (es erscheint auf keiner Stufe); Argumente mit einem Namen der
> festen Secret-Klasse (`password`, `token`, `api_key` …) bleiben auf jeder Stufe
> geschwärzt. Nicht im Werkzeug deklarierte Argumente behalten auf jeder Stufe
> ihren Namen, ihr Wert wird `[REDACTED]` — auch im Inhalts-Export.
> Weist die zentrale Schema-Prüfung einen Aufruf vor dem Handler ab, gilt das
> für **alle** Argumentwerte, auch deklarierte: Nur Schlüsselnamen mit
> `[REDACTED]` stehen im Ereignis und im Inhalt samt Export.

Transportfehler enthalten weder die URL noch darin eingesetzte Pfad- oder
Query-Argumentwerte. Argumentfehler nennen Parametername und erwartete Form,
keine Argumentwerte. Das gilt für die Antwort an die KI und den Fehlergrund
im Audit-`Detail` auf jeder Protokolltiefe, unabhängig von `redact_params`.
Der innere Transportgrund (z. B. `connection refused`) bleibt erkennbar.

> **Automatisch redigiert:** Bei einem schreibenden Datei-Upload-Tool wird der
> File-Quell-Parameter (der base64-Inhalt) **immer** redigiert — unabhängig von
> `redact_params`. Der Datei-Inhalt landet so nie im Audit-Log. `filename` und
> `content_type` bleiben Klartext (nützliche Metadaten, kein Inhalt), außer die
> Spec führt sie in `redact_params`. Trägt der Dateiname Kundendaten, gehört er
> dorthin (`lexware-office`).
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
> deklarieren ihn nicht. Begründung und Preis: (Produkt-Doku, nicht öffentlich) §4.

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
  trifft man, „Beispielbetrieb am Markt, Inh. Beispielperson" nicht. Ein solcher Eintrag
  erzeugte den gefährlicheren Zustand — es *sähe* pseudonymisiert aus.
- **`geburtsdatum` erkennt die FORM eines Datums plus einen plausiblen
  Jahresbereich (1900–2015, fest gesetzt), nicht seine Bedeutung.** Dadurch fallen
  Rechnungs-, Fälligkeits- und Valutadaten heraus — genau die Angaben, mit denen
  der Agent arbeitet. Ein **altes Vertragsdatum oder Gründungsjahr** aus dem
  Fenster wird weiterhin getroffen: nicht blind auf jedes Freitextfeld legen.
- **Der Honigtopf wächst schneller:** ein Eintrag je **Treffer** statt je
  deklariertem Feld.

**Sicherheit & Grenzen (verbindlich):**
- ~~**Scope-gebundene Reversal**~~ — **mit #343 aufgegeben** (PO-Entscheid,
  (Produkt-Doku, nicht öffentlich) §4). Ein Token aus Connector A wird in einem Write nach
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
  Details: (Produkt-Doku, nicht öffentlich).

## Eigene Spec eines Teams (Integrations-Stufe 3)

Ein Team auf Integrations-Stufe 3 legt eine Spec in diesem Format selbst an
(Oberfläche: „Neue Integration" → „Eigene REST-Spec"; REST:
`POST /api/admin/team-integrations/{teamID}/spec`, (Produkt-Doku, nicht öffentlich)). Weil
das Team damit das Ziel bestimmt, gelten über dieses Format hinaus:

- `name` beginnt mit `<team-slug>-` und liegt — nach Kleinschreibung, `-` als
  `_` gelesen — weder im Bereich `script_` noch in dem eines
  Gateway-Werkzeugs (`memory_…`, `kartei_…`, `ping`, …); dasselbe gilt für
  jeden entstehenden Werkzeugnamen.
- `base_url` und `auth.token_url` sprechen `https` und zeigen auf einen
  öffentlichen Host (kein Loopback, link-local, CGNAT, privates Netz — auch
  nicht über einen Namen, der dorthin auflöst; geprüft bei der Anlage, beim
  Laden und bei jedem Verbindungsaufbau).
- `auth.credential` liegt im Namensraum des Teams; `auth.type:
  oauth2_on_behalf_of` und `oauth2_token_exchange` sind nicht erlaubt.
- `description`-Texte erscheinen beim Agenten bereinigt (Zeilenumbrüche zu
  Leerzeichen, Steuer- und Bidi-Zeichen entfernt, höchstens 1000 Zeichen).
- `read_via_post` ist nicht erlaubt (400): Ein `POST` ist in einer eigenen
  Spec immer ein Schreibwerkzeug (`write: true`).
- Lese-Werkzeuge stehen den Mitgliedern des Teams danach zur Verfügung;
  `write: true`-Werkzeuge gibt nur die Verwaltung tool-genau frei.
- **„Lesend" ist dabei eine Selbstauskunft des Teams:** Auch ein
  Lese-Werkzeug trägt seine Parameter an das selbst gewählte Ziel, und die
  Beschreibungen eines Mitglieds erreichen die Agenten aller Mitglieder.
  Stufe 3 heißt also: Jedes Mitglied kann Werkzeuge für die Agenten aller
  Mitglieder schreiben, die Daten an ein selbst gewähltes Ziel senden.
- **Rollback:** Senkt die Verwaltung das Team unter Integrations-Stufe 3,
  ruht die eigene Integration: Sie wird nicht geladen, aber nicht gelöscht.
- Die Spec lässt sich nicht bearbeiten — löschen und neu anlegen.

## Validierung & Probe

`connector check|selftest|privacy` und `connector upgrade` verlangen den
vorhandenen Anlagen-Master-Key (`JNPT_MASTER_KEY` oder `JNPT_MASTER_KEY_FILE`).
Ohne ihn folgen Exit 1 und eine klare Meldung vor Store/Vault; weder Datenbank
noch Schlüsseldatei werden angelegt.

```bash
jnpt connector check               # alle Connectoren prüfen
jnpt connector check demo-erp      # nur einen
```

Vier Stufen pro Connector: (1) Spec gültig, (2) Auth-Werte ausgefüllt — kein
Vorlagen-Platzhalter mehr in `auth.token_url`/`auth.client_id` (Story #709; nur
bei `auth.type: oauth2_client_credentials` relevant, siehe
[App-only-Token](#app-only-token-authtype-oauth2_client_credentials)) und —
heute bei jeder Spec — keine Null-GUID mehr in `base_url` oder einem
Werkzeug-Pfad; heute auch kein reservierter Platzhalter-Host in den
Feldern aus `connector.InstanceFields`, (3) referenziertes Credential im Vault vorhanden, (4) Probe-Aufruf gegen die echte
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
   Timeout, 4xx/5xx, eine zu große Antwort oder ein 2xx, dessen
   `response_error` `true` ergibt, ist ein Fehlschlag (`upstream_error`);
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
Upstream-Body, nie das Credential — auch wenn das Zielsystem es zurückspiegelt;
keine URL in Transportfehlern und keine Argumentwerte in Argumentfehlern).
Dasselbe Urteil liefert `POST /api/admin/connectors/{name}/selftest` (für die GUI
und externe Trigger), siehe (Produkt-Doku, nicht öffentlich).

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
Connector hinzufügt, steht in (Produkt-Doku, nicht öffentlich) (Abschnitt
„Contract-/Golden-Test-Harness"); das Harness selbst liegt in
(Produkt-Doku, nicht öffentlich).

## Wann ist dieses Format *nicht* das richtige Werkzeug?

Das Format beschreibt einen einfachen GET-Aufruf oder einen deklarierten
lesenden POST pro Tool sowie **zwei** schreibende Formen (POST + Datei-Upload,
POST + JSON-Body). Wenn du
andere Schreiboperationen (PUT/PATCH/DELETE), mehrstufige Abläufe (erst
weitere Werkzeuge aufrufen; der deklarierte Session-Login gehört zur Auth), das Hochladen mehrerer Dateien, automatisches
Durchblättern aller Seiten oder komplexe Umformungen brauchst, ist ein
**eigener (externer) MCP-Server** der bessere Weg — JanuaPort bindet ihn genauso mit
Auth und Audit an. Im Zweifel: kleiner halten und nachfragen.

Und wenn das Bestandssystem **gar keine brauchbare API hat**, aber eine
Datenbank, in die du lesen darfst: Dafür gibt es die dritte Integrationsart,
**hinterlegte, parametrisierte SQL-Abfragen als MCP-Tools** —
[`docs/db-connector-spec.md`](db-connector-spec.md) (PostgreSQL und SQL Server; deklarierte SELECT-, INSERT- und UPDATE-Tools).
Wo es eine API gibt, ist sie trotzdem vorzuziehen: Eine API ist ein Vertrag, ein
Datenbankschema nicht.
