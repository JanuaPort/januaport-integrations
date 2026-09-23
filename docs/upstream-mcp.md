# Upstream-MCP-Proxy — Format-Referenz (Story #94 + #149)

Neben deklarativen [Connectoren](connector-spec.md) (REST-APIs → MCP-Tools) kann
JanuaPort **fremde MCP-Server** proxen: Ein *Upstream* ist eine **benannte
Integration**, deren allowlisted Tools JanuaPort beim Start entdeckt und unter einem
eigenen Namensraum über den `/mcp`-Endpoint anbietet — mit **derselben** Auth,
Policy (feingranulare Scopes) und Audit-Behandlung wie ein Connector. Der erste
Fall ist der **GitHub-MCP-Server**.

> **Nicht verwechseln — dieses Dokument beschreibt die eine Richtung.** Hier
> geht es darum, wie JanuaPort **selbst Client** eines fremden MCP-Servers wird
> und dessen Tools weiterreicht. Die **Gegenrichtung** — wie ein fremder
> MCP-**Client** (n8n, ein eigener Agent, ein Skript) an JanuaPorts `/mcp`
> andockt — steht in
> `docs/mcp-client-anbindung.md` (Produkt-Doku, nicht öffentlich): Endpunkt,
> Bearer-Token, Scope-Vergabe und die drei Fußangeln für automatisierte
> Clients (keine Bestätigung, kein Auto-Retry bei Writes, jeder Token zählt
> als Zugang).

Ein Upstream ist die richtige Wahl, wenn es für ein System bereits einen
**MCP-Server** gibt (statt einer simplen REST-API, die ein Connector abdeckt).
Welche Upstreams es gibt, welcher Auth-Bucket sie trägt und wann ein Upstream statt
eines Connectors zu wählen ist, steht im
[Connector-Treue §8](connector-treue.md#8-mcp-upstreams--die-zweite-integrationsart-69);
die Doku-URLs und der Live-Stand je Upstream stehen in dessen §7-Treue-Tabelle.

> **Scope v1 (bewusst eng):** Transport ist **Streamable HTTP** (kein
> stdio/Subprozess). Auth ist **ein** statisches Header-Credential aus dem Vault
> (Default Bearer — **kein OAuth**). Kein Hot-Reload (die Specs werden **beim
> Start** geladen). Read ist Default; **Write** ist opt-in über eine separate
> Allowlist (siehe unten).

## Verzeichnis & Env

JanuaPort lädt beim Start alle `*.yaml`/`*.yml` aus dem Upstream-Verzeichnis:

| Env | Default | Bedeutung |
|---|---|---|
| `JNPT_UPSTREAMS_DIR` | `/data/upstreams` | Verzeichnis mit Upstream-Specs. Fehlt es/ist es leer → keine Upstream-Tools (kein Fehler). |

Analog zur Connector-Konvention (`JNPT_CONNECTORS_DIR`). Ist ein Upstream beim
Start **nicht erreichbar** (oder fehlt das Credential), wird er **geloggt und
übersprungen** — das Gateway startet trotzdem, die übrigen Tools sind
unbeeinträchtigt.

## Vollständiges Beispiel (GitHub, read-only)

```yaml
name: github                                  # Namespace + Policy-Identität (admin-gewählt)
description: "GitHub (read-only PAT)"          # optional: unterscheidet mehrere Instanzen
url: https://api.githubcopilot.com/mcp/        # Streamable-HTTP-Endpoint des Upstream-MCP-Servers

auth:                                          # exakt die Connector-Spec-Form
  header: Authorization
  template: "Bearer {{credential}}"            # {{credential}} = das Vault-Secret
  credential: github-mcp-pat                   # Name des Secrets im Vault

headers:                                       # optional: statische, NICHT-geheime Extra-Header
  X-MCP-Toolsets: "repos,issues,pull_requests" # z. B. Toolset-Auswahl des GitHub-Servers

tools:                                         # Pflicht-Allowlist der READ-Tools (deny-by-default)
  - search_issues
  - get_file_contents
  - list_pull_requests
```

Das Secret wird **vorher** im Vault angelegt (nie in der Spec):

```bash
jnpt credential set --name github-mcp-pat      # PAT über stdin (nicht in der Shell-History)
```

Die qualifizierten Tool-Namen sind `<name>_<tool>` (Bindestriche → Unterstriche):
`github_search_issues`, `github_get_file_contents`, … Ein Token braucht den
passenden Scope, sonst sieht es die Tools nicht:

```bash
jnpt token create --allow github                       # ALLE Read-Tools der Instanz „github"
jnpt token create --allow github:search_issues         # nur dieses eine Tool
```

## Felder

### Oberste Ebene

| Feld | Pflicht | Bedeutung |
|---|---|---|
| `name` | ja | Eindeutiger Instanz-Name. **Namespace-Präfix** jedes Tool-Namens **und** Policy-Identität (Scope). Kleinbuchstaben/Ziffern/`-`/`_`, beginnt mit Buchstabe. **Reserviert** (das Gateway belegt diese Namen selbst — eine Integration dieses Namens verhindert den Start): `memory`, `kartei`, `usecase` (#642), `wissen` (#647), `ablage` (#726), `ping`, `catalog`, `report_problem`. |
| `description` | nein | Wird der Upstream-Tool-Beschreibung vorangestellt (`<description> — <upstream-desc>`) — damit mehrere Instanzen desselben Providers fürs Agent-Routing unterscheidbar sind. |
| `url` | ja | Streamable-HTTP-Endpoint des Upstream-MCP-Servers (`http(s)://…`). **Muss die exakte Endpoint-URL sein** — JanuaPort folgt keinen Redirects (Credential-Leak-Schutz). |
| `auth` | ja | Wie das Vault-Credential in jeden Request kommt (siehe unten). |
| `headers` | nein | Statische, **nicht-geheime** Extra-Header (map). **Nie** den Auth-Header hier setzen (Secrets nur über `auth`/Vault → Startfehler). |
| `tools` | ja¹ | Allowlist der **Read**-Tool-Namen (unqualifiziert, wie der Upstream sie nennt). Leer/fehlend = keine Read-Tools. |
| `write_tools` | nein | Allowlist der **Write**-Tool-Namen (siehe [Write-Tools](#write-tools-149)). Leer/fehlend = keine Writes. |
| `endpoint_view` | nein | `true` macht diese Integration zu einem eigenen **benannten MCP-Endpoint** `/mcp/v/<name>` (#164) — der Client sieht dann NUR die Tools dieser Integration als eigene „Integration". Reine Sicht (effektive Tools = `Scope ∩ View`); Auth identisch zu `/mcp`. Default `false`. **Seit #216 ist das der ANLAGE-Default:** der Schalter lässt sich nachträglich in der Admin-GUI bzw. über `PUT /api/admin/integrations/{name}/endpoint-view` umstellen — der einzige Schreibpfad auf eine Upstream-Instanz (die Spec selbst bleibt datei-basiert), wirkt ohne Neustart und überstimmt diesen Wert in beide Richtungen. |

¹ Formal ist `tools` optional (leer = deny-by-default = nichts), aber ohne
`tools` **und** ohne `write_tools` registriert der Upstream nichts.

### `auth` (identisch zur Connector-Spec)

| Feld | Pflicht | Bedeutung |
|---|---|---|
| `header` | ja | Name des HTTP-Headers, meist `Authorization`. |
| `template` | ja | Header-Wert mit Platzhalter `{{credential}}`, z. B. `"Bearer {{credential}}"`. |
| `credential` | ja | **Name** des Secrets im Vault (nie das Secret selbst). |

## Write-Tools (#149)

Standardmäßig ist ein Upstream **read-only**. Schreibende Tools werden über eine
**separate, explizite Allowlist** freigegeben — nie aus `tools` ableitbar:

```yaml
write_tools:
  - create_issue
  - add_issue_comment
```

Verhalten schreibender Upstream-Tools (überträgt die
#58-Write-Semantik (Produkt-Doku, nicht öffentlich) auf den Proxy):

- **Tool-genauer Scope Pflicht.** Ein Write-Tool wird von einem **instanz-weiten**
  Scope (`github`) **nicht** erfasst — es verlangt `github:create_issue`. „Gib dem
  Token GitHub" gibt so nie versehentlich Schreibrechte.
- **Annotations (serverseitig).** Write-Tools tragen `readOnlyHint:false` (ein
  Client wie Cowork kann vor dem Aufruf bestätigen lassen); `destructiveHint` wird
  vom Upstream durchgereicht (fehlt er → unbekannt). Die echte Leitplanke ist
  serverseitig (Scope + Audit), die Hints sind beratend.
- **Audit.** Ein relayter Write-Call wird als `write` markiert
  (`jnpt audit list --write`). Scheitert das Audit-Schreiben **nach** einem
  erfolgreichen Call, sieht der Agent einen Fehler, obwohl der Write evtl. schon
  stattfand — die Meldung bittet dann, im Zielsystem zu prüfen statt blind zu
  wiederholen.
- **Keine automatischen Retries.** Der MCP-Client sendet einen `tools/call` genau
  **einmal** (kein automatischer Write-Retry) — wichtig, weil ein Write nicht
  idempotent ist.

### Verantwortungsmodell: Read/Write-Klassifikation

Die **Zuordnung eines Tools zu `tools` (read) oder `write_tools` (write) liegt beim
Betreiber** — JanuaPort kann die Semantik eines fremden Tools nicht erraten. Als
**Backstop** vertraut JanuaPort den Annotations des Upstreams aber **in die strengere
Richtung**:

- Steht ein Tool in `tools` (read), der Upstream annotiert es aber ausdrücklich als
  **destruktiv** (`destructiveHint`), lehnt JanuaPort den **Start ab** (fail-closed) —
  verschiebe es nach `write_tools` oder entferne es.
- **Grenze (ehrlich):** Das MCP-Protokoll drückt „read-only" über ein einfaches
  boolesches `readOnlyHint` aus. Ein Upstream, der ein Tool **nur** mit
  `readOnlyHint:false` (ohne `destructiveHint`) meldet, ist über den Go-MCP-Client
  nicht sicher von „gar nicht annotiert" zu unterscheiden — dieser Fall wird vom
  Backstop **nicht** erkannt. **Die Allowlist des Betreibers ist die primäre
  Kontrolle**, ergänzt um tool-genauen Scope und Audit.

## Mehrere Instanzen desselben Providers (Instanz-Modell)

`name` ist die Instanz-Identität. Zwei Specs dürfen **dieselbe URL** mit
**unterschiedlichen** Credentials, Allowlists und Namespaces nutzen — z. B. ein
read-only-PAT mit breitem Read-Zugriff und ein eng berechtigter Write-PAT nur für
ein Team-Repo:

`github-readonly.yaml`:

```yaml
name: github-readonly
description: "GitHub read-only (org-weiter PAT)"
url: https://api.githubcopilot.com/mcp/
auth:
  header: Authorization
  template: "Bearer {{credential}}"
  credential: github-readonly-pat        # PAT mit nur Lese-Scopes
tools:
  - search_issues
  - get_file_contents
  - list_pull_requests
# kein write_tools → diese Instanz kann nichts schreiben
```

`github-support.yaml`:

```yaml
name: github-support
description: "GitHub Support (schreibt nur im Support-Repo)"
url: https://api.githubcopilot.com/mcp/
auth:
  header: Authorization
  template: "Bearer {{credential}}"
  credential: github-support-pat         # PAT, dessen GitHub-Rechte auf 1 Repo + Issues begrenzt sind
tools:
  - search_issues
write_tools:
  - create_issue
  - add_issue_comment
```

Ergebnis: getrennte Tool-Namensräume (`github_readonly_search_issues` vs.
`github_support_create_issue`), getrennte Vault-Credentials, getrennte Scopes.
Ein Token bekommt gezielt, was es braucht:

```bash
jnpt credential set --name github-readonly-pat
jnpt credential set --name github-support-pat
jnpt token create --allow github-readonly                       # nur Lesen (org-weit)
jnpt token create --allow github-support:create_issue \
                  --allow github-support:add_issue_comment       # nur Support-Writes
```

> **Doppelte Sicherheit:** Die eigentliche Berechtigung liegt am **PAT** (was
> GitHub erlaubt) **und** am **JanuaPort-Scope** (welches Tool der Token aufrufen darf).
> Beide zusammen begrenzen den Blast-Radius.

## Scope-Vergabe: Upstream-Instanzen wie Connectoren (#151)

Für die **Scope-Vergabe** (welcher Token/welche SSO-Identität ein Tool aufrufen
darf) behandelt JanuaPort eine Upstream-Instanz exakt wie einen Connector — derselbe
`connector`- bzw. `connector:tool`-Scope-String, dieselbe Validierung
(`jnpt token allow`, `JNPT_SSO_DEFAULT_SCOPE`, `JNPT_SSO_GROUP_SCOPES`, die
Admin-API). Die **Spec-Allowlist** (`tools`/`write_tools`) ist dabei die gültige
Scope-Fläche — die Validierung braucht **keinen erreichbaren Upstream**: Weder
`jnpt token allow` noch der Serverstart verbinden sich dafür. Das gilt
ausdrücklich auch für eine beim Start **nicht erreichbare** Instanz (geloggt +
übersprungen, s. o.) — sie bleibt trotzdem scope-vergebbar, damit ein temporär
toter Upstream keine Ausfall-Falle für `JNPT_SSO_DEFAULT_SCOPE`/
`JNPT_SSO_GROUP_SCOPES` wird.

```bash
jnpt token create --allow github                       # ALLE Read-Tools der Instanz „github"
jnpt token create --allow github:create_issue           # nur dieses eine Write-Tool
jnpt token allow <token-id> github:search_issues        # nachträglich (wirkt sofort)
```

**SSO-Default-Scope** (Story #86) und **Gruppen→Scope-Mapping** (Story #114)
akzeptieren dieselben Scope-Strings — auch auf Upstream-Instanzen:

```bash
# jede gültige SSO-Identität sieht alle Read-Tools der Instanz "github"
JNPT_SSO_DEFAULT_SCOPE=github

# gemischt: ein Connector-Scope + ein tool-genauer Upstream-Write-Scope
JNPT_SSO_DEFAULT_SCOPE=demo-erp,github:create_issue

# Gruppen-Claim → Scope-Mapping (wert=scope1,scope2;wert2=…), auch mit Upstreams
JNPT_SSO_GROUP_SCOPES="11111111-…=github:search_issues;22222222-…=github"
```

Die **Write-Invariante** aus [#149](#write-tools-149) bleibt unangetastet: ein
instanz-weiter Scope (`github`) erfasst `write_tools` weiterhin **nicht** — für
`create_issue`/`add_issue_comment` ist immer der tool-genaue Scope
(`github:create_issue`) nötig, egal ob er per Token, SSO-Default- oder
Gruppen-Scope vergeben wird.

## Grenzen (bewusst)

- **Kein OAuth** (nur statisches Header-Credential aus dem Vault). Kein
  stdio/Subprozess-Transport. Keine Multi-Server-Orchestrierung.
- **Kein Hot-Reload:** Specs werden beim Start geladen. Eine Änderung greift nach
  einem Neustart (`docker compose up -d` nach Ablegen der Datei). Ein
  laufzeit-getriggerter Reload ist eine Folge-Story (#63-Naht).
- **Keine semantische Reversibilitäts-Garantie** für fremde Write-Tools — die
  Kontrolle ist Operator-Allowlist + tool-genauer Scope + Audit; Client-seitige
  Bestätigung bleibt beratend.
- **Die Antwortform des fremden Servers wird nicht korrigiert (#457).** Die
  MCP-Spezifikation definiert `structuredContent` als *„an optional JSON
  object"*. Legt ein angebundener Server dort ein **Array auf oberster Ebene**,
  ist das spec-widrig — tolerante Clients schlucken es, strikte verwerfen die
  **komplette** Antwort. JanuaPort reicht diese Antwort **unverändert** durch.

  Das ist eine bewusste Entscheidung und keine Lücke: Der fremde Server
  deklariert sein eigenes `outputSchema`. Würden wir seine Antwort in eine Hülle
  heben, liefe sie gegen seine eigene Deklaration — wir ersetzten eine fremde
  Spec-Verletzung durch eine eigene, und ein Client, der das Schema kennt,
  bekäme ein neues Problem. **Der Weg zur Lösung führt über den Betreiber des
  angebundenen Servers.** Für JanuaPorts *eigene* Integrationsarten gilt die
  Regel dagegen ausnahmslos: REST-Listen reisen als `{"items": […]}`
  ([`docs/connector-spec.md`](connector-spec.md)), Datenbank-Zeilen als
  `{"rows": […]}` ([`docs/db-connector-spec.md`](db-connector-spec.md)).
