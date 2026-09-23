# Connector-Treue — Auth-Muster, Bau-Disziplin, MCP-Upstreams

Die verbindlichen Regeln für eine Spec in diesem Repository: **welche
Auth-Muster** es gibt (§1), **welche Disziplin** beim Bauen und Ändern gilt —
Doku-Referenz, Envelope-Parität, Live-Beleg als Definition of Done (§7) — und
**wann ein fremder MCP-Server der bessere Weg** ist als eine eigene Spec (§8).

> **Herkunft und Grenzen.** Dies ist ein Auszug aus der internen
> Connector-Landschaft der JanuaPort GmbH; die Abschnittsnummern sind die des
> Originals. Bewusst **nicht** hier: die Priorisierung des Eigenbaus, die
> DACH-Marktübersicht und die Recherche-Liste (§2–§6) — das ist unsere
> Roadmap, kein Vertrag. Die **#-Nummern** verweisen auf das Backlog des
> Produkt-Repositoriums, das heute geschlossen ist; sie nennen die Herkunft
> einer Entscheidung und sind kein Link.

> **Zwei Integrationsarten — die Wahl fällt vor dem Bau.**
> §1 und §7 beschreiben den **deklarativen Connector** (YAML → REST-Call → MCP-Tool,
> `docs/connector-spec.md`). **§8** beschreibt den **MCP-Upstream**: ein System, für
> das es bereits einen MCP-Server gibt, wird geproxt statt nachgebaut
> (`docs/upstream-mcp.md`). Faustregel: **Gibt es einen MCP-Server, ist er der Weg** —
> ein Connector, der einen vorhandenen MCP-Server in YAML nachbaut, ist doppelte
> Arbeit mit halber Abdeckung. Systeme **ohne** brauchbare API (nur Datenbank) haben
> heute **keine** Integrationsart — eine bewusste, offen benannte Lücke.

## 1. Auth-Muster-Buckets (tragend für den Connector-Framework + #64)

Quer über ~25 Systeme gibt es vier Muster. Häufigkeit bestätigt die
Priorisierung in **#64**:

| Bucket | Systeme (Auswahl) | JanuaPort-Status |
|---|---|---|
| **OAuth2 client-credentials** (M2M, unbeaufsichtigt) | Business Central (S2S), Personio v2, Salesforce, M365/Graph (app-only), DATEV, PayPal | **#64 Prio 1** — bauen |
| **Statischer API-Key/Token im Header** | HubSpot (Private App), Pipedrive, CentralStationCRM, Factorial, d.velop, Xentral (PAT), JTL-Wawi, Stripe, Mollie, Lexware ✓ | **heute schon möglich** |
| **OAuth2 authorization-code + refresh** (per-User) | HubSpot Public, Pipedrive OAuth, Google Workspace, M365 delegated | **#64 später** (+ #45/#65) |
| **Custom Token-Exchange / Basic + Discovery** | Personio v1, HeavenHR, DocuWare (password grant + `IdentityServiceInfo`), ELO (Basic) | Sonderfälle → ggf. externer MCP-Server |


## 7. Connector-Treue: Doku-Referenz, Envelope-Parität, Live-DoD

Verbindliche Disziplin beim Bauen/Ändern eines Connectors (Lehre #49/#51/#73). **Für MCP-Upstreams (§8) gilt sie sinngemäß:**
Punkt 1 und 3 unverändert; an die Stelle der Envelope-Parität (Punkt 2) tritt der
Abgleich von **Endpoint-URL und Tool-Namen gegen den echten Server** — den HTTP-Envelope
verantwortet dort der MCP-Client, nicht unsere Runtime.

1. **Doku-Referenz pro Connector pflegen** (Tabelle unten): die offiziellen
   Doku-URLs (idealerweise pro Endpunkt) **und** das kanonische Request-Beispiel
   inkl. **Header/Auth**. „Erst aus der Doku arbeiten" gilt explizit auch für den
   Request-Envelope, nicht nur für Endpunkt/Parameter/Antwort.
2. **Envelope-Parität:** Doku-Beispiel (Methode, Pfad, Query **und Header**) gegen
   das abgleichen, was JanuaPort real sendet. Der Runtime gehören `Authorization`
   (aus `auth`), `Content-Type` (aus `encoding`), `Content-Length`/`Host` und der
   Default-`Accept: application/json` (#73). Jeden **weiteren** festen Header
   deklariert seit **#347** die Spec selbst: `headers:` auf Connector- oder
   Tool-Ebene (Tool gewinnt) — **nur konstante Werte, nie ein Credential**, die
   vier Runtime-Header werden beim Laden abgewiesen. Braucht ein Connector einen
   **dynamischen** Header (Wert aus einem Tool-Parameter), ist das weiterhin eine
   Format-Frage: eskalieren, nicht heimlich bauen.
3. **Live-200 als Definition of Done:** kein Tool ist „fertig" ohne einen echten
   Erfolg gegen die echte API (200 read / kontrollierter Erfolg write), **im
   Issue dokumentiert**. Braucht einen echten Account → bewusster PO/Tester-Schritt.

| Connector | Doku | Auth | Envelope-Notiz |
|---|---|---|---|
| lexware-office | developers.lexware.io/docs | Bearer API-Key | **Alle** Doku-Beispiele senden `Accept: application/json`; `/v1/vouchers/{id}` 400t **ohne** `Accept` (`/v1/voucherlist` ist tolerant). Rate ~2 req/s. Live-verifiziert (#73): `GET /v1/vouchers/{id}` → 200 mit `files[]`. |
| microsoft-graph-mail | learn.microsoft.com/graph/api/`user-list-messages` · `message-get` · `user-post-messages`; Postfach-Begrenzung: learn.microsoft.com/exchange/permissions-exo/application-rbac | OAuth2 client-credentials (app-only, Scope `https://graph.microsoft.com/.default`) | Doku-Pflicht: `Authorization: Bearer …`, beim POST `Content-Type: application/json` (kommt aus `encoding: json`) + `Content-Length` (setzt Go selbst). `Accept` verlangt Graph nicht, die Runtime setzt ihn ohnehin. `get_message` sendet seit **#347** den statischen Header `Prefer: outlook.body-content-type="text"` (Klartext statt HTML) — eine **Bitte**, keine Zusage: was ankam, sagt `body.contentType`. `$filter` und `$search` sind am Nachrichten-Endpunkt **nicht kombinierbar**; `$orderby` verlangt, dass die Sortier-Property auch (und zuerst) im `$filter` steht. Kein `check: true`-Tool (jedes Tool braucht `mailbox`) → `connector check` endet nach Stufe 3 (Auth-Werte-Stufe #709 dazwischen `ok`, sofern `token_url`/`client_id` nicht mehr die Vorlagen-Platzhalter tragen). **Live belegt (06./07.08.2026, #332):** Lesen mit 200, Entwurf real angelegt samt Gegenprobe „nichts versendet"; `Prefer` wirkt (`body.contentType` = `text`). **Auch die Ein-Postfach-Grenze ist belegt** (13.08.2026, #344): Die Grenze läuft über **RBAC for Applications** (ManagementScope auf genau eine SMTP-Adresse, Entra-Consent entfernt) — das erlaubte Postfach lieferte Nachrichten, ein zweites, nachweislich existierendes antwortete mit **403**. Der Negativ-Test lief damit gegen ein echtes Postfach; der alte 404-Fehlschluss ist erledigt. ⚠️ Undeklarierte Antwortfelder: `$select` entfernt die OData-Metafelder **nicht** (`@odata.context`/`@odata.etag`) — die Tools projizieren seit #368 explizit. Gilt für jeden OData-Upstream. |
| microsoft-graph-sharepoint | learn.microsoft.com/graph/api/`site-get` · `drive-list` · `driveitem-list-children` · `driveitem-get` · Ressource `resources/driveitem`; Berechtigungsmodell: learn.microsoft.com/graph/permissions-selected-overview + `site-post-permissions`; Blättern: learn.microsoft.com/graph/paging (alle 20.08.2026 geprüft) | OAuth2 client-credentials (app-only, Scope `https://graph.microsoft.com/.default`), **eigenes** Vault-Credential — die Mail-App wird NICHT erweitert | Doku-Pflicht ist allein `Authorization: Bearer …`; alle vier Tools sind GET ohne Body, `Accept` verlangt Graph nicht (die Runtime setzt ihn ohnehin), deshalb **kein** `headers:`-Block. **Berechtigung:** `Sites.Selected` — der Admin-Consent gibt **null** Zugriff, erst ein per-Site-Grant (`POST /sites/{siteId}/permissions`, `"roles": ["read"]`, durch einen Tenant-Admin) öffnet genau eine Site; er vererbt sich auf alle Bibliotheken der Site. Fehlender Grant ⇒ **403** (nicht 401 — „Freigabe prüfen", nicht „Credential erneuern"). Site-Adresse steht **fest in der Spec** (eine Integration = eine Site), `get_site` ist `check: true` → `connector check` läuft bis Stufe 4. **Paginierung** über `$top` + `$skipToken`/`@odata.nextLink` (**kein** numerisches `$skip`), kein Auto-Paging. ⚠️ **`@microsoft.graph.downloadUrl` ist eine vorauthentifizierte URL** („Authentication isn't required with this URL") — wird nirgends angefordert UND von jeder Projektion abgeschnitten (die Runtime hat dafür keine Sperre; `$select` entfernt `@…`-Felder nicht zuverlässig, #368). Deshalb **kein Content-Tool**: `GET …/content` antwortet 302 auf ebendiese URL, und die Runtime folgt bewusst keinem Redirect (#119). **Drosselung:** keine `RateLimit-*`-Header, nur `Retry-After` bei 429/503; ein Versuch ohne Rückzug (#397, Umsetzung #485). **Status: gebaut (#551), am echten Tenant live belegt (25.08.2026)** — `get_site` **403 vor** dem Site-Grant und **200 danach ohne Neustart** (der Grant wirkt ressourcenseitig, nicht im Token), `list_libraries` und `list_children` mit echten Metadaten — und der Wächter fand in keiner Antwort eine `downloadUrl`. |
| dokumente | `JanuaPort/januaport-rag` `docs/suchdienst-api.md` (§1 Endpunkte, §2 Beispielantworten, §3 Fehlerbilder) + das `/openapi.json` des Dienstes selbst — beide 19.09.2026 geprüft | Statischer Bearer (Auth-Bucket A) über den `auth`-Block, **eigenes** Vault-Credential je Wissensbereich — kein OAuth2 | Doku-Pflicht ist allein `Authorization: Bearer …`; alle vier Tools sind GET ohne Body, `Accept` verlangt der Dienst nicht (die Runtime setzt ihn ohnehin), deshalb **kein** `headers:`-Block. **Der Wissensbereich steht fest in der `base_url`** (`/bereiche/<bereich>`), nie in Pfad/Query eines Tools — eine Team-Sicht kann ihn sonst nicht einschränken (#385); `dokumente.yaml` ist damit die **erste** ausgelieferte Spec mit einem Pfad-Prefix in `base_url` (Harness entsprechend nachgezogen, #760). **Weggelassene Optionen entfallen ganz:** kein `top_k` → kein `top_k` im Query, kein `context` → kein `context` im Query (Golden-Beleg der Vertrags-Tests). **Fehlerbilder:** 401 trägt keinen Grund im Body und ist **kein Existenz-Orakel** (ein unbekannter Bereich antwortet mit falschem Schlüssel identisch zu einem echten); 404 unterscheidet nicht zwischen „gibt es nicht" und „anderer Bereich"; 422 bei `top_k` > 20 oder `q` < 2 Zeichen; 503 adressenlos (Index/Embedding nicht erreichbar). ⚠️ **`score` ist die fusionierte RRF-Rangzahl, KEINE Kosinus-Ähnlichkeit** — nur innerhalb einer Antwort sinnvoll sortierbar, nicht über mehrere Suchen hinweg vergleichbar. **Status: LIVE BELEGT 20.09.2026 auf der Showcase (#762)** — `jnpt connector check` alle vier Stufen grün gegen den echten Suchdienst (Probe `get_area_status`), MCP-`search` über `/mcp` mit Wegwerf-Token: erwartete Quelle `werknormen/wn-003_rev_b.pdf` und „höchstens 8 µS/cm" unter den Treffern, Audit-Eintrag `read ok` mit redigiertem `q`. Betrieb der Showcase-Instanz: `docs/deploy-hetzner.md` §14. |
| github (Upstream, §8) | Server + Header/Pfad-Modifikatoren: github.com/github/github-mcp-server (`docs/remote-server.md`); PAT: docs.github.com/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens — beide 2026-08-10 geprüft | Statischer Bearer (fine-grained PAT) über den `auth`-Block; **kein OAuth** (v1-Grenze #69) | Der Envelope gehört hier dem MCP-Client, nicht unserem Runtime — geprüft wird stattdessen die **Endpoint-URL** (`https://api.githubcopilot.com/mcp/`, exakt; JanuaPort folgt keinen Redirects) und die **Allowlist gegen die real gemeldeten Tool-Namen**. ⚠️ GitHub hat die Namen konsolidiert (`issue_read`/`issue_write` statt `get_issue`/`create_issue`) — Namen **immer** gegen `tools/list` des echten Servers abgleichen, nie aus der Doku abschreiben. Statische Header laut Doku: `X-MCP-Toolsets` (Komma-Liste), `X-MCP-Readonly`, `X-MCP-Insiders`; dieselben Wirkungen auch als Pfad-Modifikator (`/x/{toolset}`, `/readonly`). **Empfehlung für Read-Instanzen:** zusätzlich `X-MCP-Readonly` bzw. `/readonly` setzen — dann ist unsere Allowlist nicht die einzige Linie, sondern die zweite. |

## 8. MCP-Upstreams — die zweite Integrationsart (#69)

Ein **Upstream** ist ein fremder MCP-Server, den JanuaPort unter die eigene Governance
stellt: JanuaPort entdeckt beim Start dessen Tools, bietet die **allowlisteten** unter
einem eigenen Namensraum über `/mcp` an und legt **dieselbe** Auth, Policy und
Audit-Behandlung darüber wie über einen Connector. Format und Betreiber-Anleitung:
**`docs/upstream-mcp.md`**. Beispiel-Spec: `upstream-specs/github.yaml`.

**Wann Upstream, wann Connector?**

| | Deklarativer Connector (§1–§7) | MCP-Upstream (§8) |
|---|---|---|
| Voraussetzung | System hat eine brauchbare REST-API | Für das System existiert bereits ein **MCP-Server** |
| Wir bauen | YAML je Endpunkt → Tool | eine Spec je **Integration** (URL + Credential + Allowlist) |
| Tool-Beschreibungen | schreiben **wir** (Produktfeature) | kommen vom Upstream (unser `description` wird vorangestellt) |
| Auth heute | API-Key/Bearer, OAuth2 client-credentials (#330) | **nur** ein statisches Header-Credential — **kein OAuth** |
| Aufwand | Bau + Pflege je Endpunkt | Konfiguration |

Die Faustregel steht oben: **gibt es einen MCP-Server, ist er der Weg.** Ihn in YAML
nachzubauen ist doppelte Arbeit mit halber Abdeckung — und wir müssten Tool-Texte
pflegen, die der Hersteller schon pflegt.

### Auth-Bucket „statischer Bearer (PAT)"

Upstreams fallen heute ausnahmslos in Bucket 2 aus §1: **ein** statisches Credential aus
dem Vault, per `auth`-Block in jeden Request. Das ist eine **bewusste v1-Grenze** (#69),
keine Lücke im Katalog: Ein MCP-Server, der OAuth verlangt, ist heute **nicht**
anbindbar — das hängt an #64/#45b. Wer einen solchen Fall findet: eskalieren, keinen
Sonder-Auth-Pfad bauen.

### Instanz-Modell (#148) — der eigentliche Hebel

Eine Upstream-Spec ist eine **benannte Integration**, nicht „der GitHub-Connector".
`name` ist zugleich Namensraum der Tools und Policy-Identität. Mehrere Specs dürfen
**dieselbe URL** mit **unterschiedlichen** PATs und Allowlists nutzen — genau so wird aus
einem groben PAT eine fein berechtigte Fläche:

- `github` — org-weiter read-only-PAT, breite Read-Allowlist
- `github-write` — eng berechtigter PAT, nur Issues eines Repos, `write_tools`
- `github-meineorg` — read + Issues schreiben für die eigene Org

**Live belegt** auf dem Showcase (23.07.2026, #94): drei Instanzen desselben Providers
parallel, je eigenes Vault-Credential, eigene Allowlist, eigener Namensraum.
Write-Tools verlangen dabei **tool-genauen** Scope (`github-meineorg:issue_write`);
ein instanz-weiter Scope (`github-meineorg`) erfasst sie **nicht** (#149) — „gib dem
Token GitHub" vergibt so nie versehentlich Schreibrechte.

### Katalog der Upstreams

| Upstream | Server | Auth | Status |
|---|---|---|---|
| **GitHub** ⭐ Showcase erster Reihe | `https://api.githubcopilot.com/mcp/` (offiziell, GitHub-gehostet) | fine-grained PAT (Bearer) | **ausgeliefert seit v0.2.0**; read (#94) + write (#149); Live-Stand siehe unten |
| Atlassian (Jira/Confluence) | `https://mcp.atlassian.com/v1/mcp` (Streamable HTTP) | ⚠️ **OAuth 2.1 authorization_code** mit Browser-Consent — der statische API-Token-Weg ist Preview/Org-Admin-gated und umgeht laut Atlassian die OAuth-Allowlists, deshalb **bewusst verworfen** | **blockiert**, nicht gebaut (**#85**): braucht den OAuth-Broker (#45) + #64 item 3 |
