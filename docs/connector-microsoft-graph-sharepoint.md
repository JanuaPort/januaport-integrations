# SharePoint-Dokumentbibliothek anbinden (Connector `microsoft-graph-sharepoint`)

Betreiber-Anleitung für den Graph-Connector aus
`connector-specs/microsoft-graph-sharepoint.yaml` (Story #551, PO-Go 20.08.2026).
Zielgruppe: wer den Mandanten verwaltet und JanuaPort betreibt. Programmierkenntnisse
sind nicht nötig, ein Tenant-Admin-Zugang (SharePoint-Administrator oder höher)
schon.

## 1. Was der Connector kann — und was er ausdrücklich nicht kann

**Vier Werkzeuge, alle lesend:**

| Tool | Was es tut | Art |
|---|---|---|
| `microsoft_graph_sharepoint_get_site` | die **eine** angebundene Site zeigen (Name, webUrl, Zeitstempel) | lesend, **Probe-Aufruf** |
| `microsoft_graph_sharepoint_list_libraries` | die **Dokumentbibliotheken** dieser Site auflisten | lesend |
| `microsoft_graph_sharepoint_list_children` | den Inhalt **eines Ordners** auflisten (Dateien und Ordner) | lesend |
| `microsoft_graph_sharepoint_get_item` | die Metadaten **eines** Elements holen | lesend |

**Es gibt kein Schreib-Tool** — kein Hochladen, kein Anlegen, kein Verschieben,
kein Löschen. Die App bekommt die Rolle `read`, nicht mehr.

> ⚠️ **Der Connector liest NUR METADATEN — nie den Inhalt einer Datei.** Ein
> Agent erfährt: welche Dateien und Ordner es gibt, wie sie heißen, wie groß sie
> sind, wann sie zuletzt geändert wurden und wo ein Mensch sie findet
> (`webUrl`). Er bekommt **nie** den Inhalt und **nie** einen Download-Link.
>
> Das ist kein vergessenes Feature, sondern eine Entscheidung mit einem Grund:
> Graph liefert Datei-Inhalte über eine **vorauthentifizierte URL**
> (`@microsoft.graph.downloadUrl` bzw. eine 302-Weiterleitung darauf). Diese URL
> braucht **keine Anmeldung** — wer sie sieht (der Agent, das Audit-Log, ein
> Chat-Transkript, ein weitergeleiteter Screenshot), lädt die Datei an jeder
> JanuaPort-Prüfung vorbei, bis sie nach etwa einer Stunde abläuft. Der
> Connector fordert sie deshalb nirgends an und projiziert sie nirgends.
>
> **Wenn Agenten Datei-INHALTE brauchen** (z. B. CSV-Auswertung), ist der Weg
> ein anderer: ein Beisteller holt die Dateien in das kontrollierte Verzeichnis,
> und die Datei-Integrationsart liest sie dort — inklusive der
> Pseudonymisierung, die der direkte Weg nie hätte. Das ist ein eigener Schnitt
> und nicht Teil dieses Connectors.

**Ebenfalls nicht dabei** (bewusste Grenzen dieser Version): Suche über die
Bibliothek, Versionen, Berechtigungen, Listen-Elemente außerhalb von
Dokumentbibliotheken, OneDrive-Postfächer einzelner Nutzer, automatisches
Durchblättern aller Seiten — und eine **zweite Site**.

**Eine Integration = eine Site.** Die Governance-Grenze von `Sites.Selected` ist
die Site; deshalb steht die Site-Adresse fest in der Spec und ist kein
Werkzeug-Parameter. Wer eine zweite Site anbinden will, legt eine **zweite
Integration** an: eigene Spec-Kopie, eigenes Vault-Credential, eigener Grant.

## 2. Die Einrichtung in fünf Schritten

1. **Eigene** App-Registrierung in Microsoft Entra ID anlegen
2. Berechtigung `Sites.Selected` (Anwendung) erteilen und Admin-Consent geben
3. Client Secret in den JanuaPort-Vault legen
4. **Die eine Site für diese App freigeben (Site-Grant, `roles: ["read"]`)**
5. Spec anpassen, laden und in JanuaPort berechtigen

> ⚠️ **Schritt 4 ist keine Feinheit, sondern die eigentliche Freigabe.** Anders
> als bei anderen Graph-Berechtigungen gibt der Admin-Consent aus Schritt 2
> **null Zugriff**. `Sites.Selected` heißt wörtlich: „diese App darf auf
> ausgewählte Sites zugreifen — welche, sagt jemand später einzeln." Ohne
> Schritt 4 antwortet Graph auf jeden Aufruf mit **403**, und das ist richtig
> so.

## 3. Schritt 1 — Eigene App-Registrierung

Im [Microsoft Entra Admin Center](https://entra.microsoft.com) →
**App-Registrierungen** → **Neue Registrierung**:

- Name z. B. `JanuaPort — SharePoint-Lesezugriff` (der Name taucht später in
  Protokollen und im Site-Grant auf).
- Kontotypen: **nur Konten in diesem Organisationsverzeichnis**.
- Redirect-URI: **keine**. Dieser Zugriff läuft app-only, es gibt keinen
  Anmeldedialog.

> ⚠️ **Eine EIGENE App — die Mail-App wird nicht erweitert.** Wer
> `microsoft-graph-mail` bereits betreibt, ist versucht, dort einfach
> `Sites.Selected` zu ergänzen. Nicht tun: Ein Credential, das **Postfach UND
> Dokumente** kann, ist genau die Bündelung, gegen die dieses Produkt antritt.
> Zwei Apps heißen zwei Client-IDs, zwei Client Secrets, zwei getrennte
> Widerrufe — und ein abgelaufenes Secret legt nur eine der beiden Strecken
> still. (Die Token-Caches sind ohnehin je Connector getrennt.)

Notiere aus der Übersicht:

- **Anwendungs-(Client-)ID** → kommt in die Spec (`auth.client_id`, kein Secret)
  **und** in den Site-Grant aus Schritt 4.
- **Verzeichnis-(Mandanten-)ID** → kommt in die Spec (in die `auth.token_url`).

Dann **Zertifikate & Geheimnisse** → **Neuer geheimer Clientschlüssel**. Der Wert
ist **nur einmal** sichtbar; er geht in Schritt 3 direkt in den Vault und
**nirgendwo sonst hin** (keine Datei, kein Ticket, keine Chat-Nachricht). Notiere
dir das **Ablaufdatum** — an dem Tag steht der Connector still, bis ein neues
Secret im Vault liegt.

## 4. Schritt 2 — Berechtigung `Sites.Selected` und Admin-Consent

**API-Berechtigungen** → **Berechtigung hinzufügen** → **Microsoft Graph** →
**Anwendungsberechtigungen** → `Sites.Selected` → danach
**Administratorzustimmung erteilen**.

Genau diese eine Berechtigung, sonst keine. Insbesondere **nicht**
`Sites.Read.All`: Die gilt **mandantenweit für jede Site** und macht die
Site-Freigabe aus Schritt 4 wirkungslos — dieselbe Falle wie eine
mandantenweite `Mail.ReadWrite` ohne Postfach-Grenze. Auch die feineren
`*.SelectedOperations.Selected`-Berechtigungen (Dateien, Listen, Listenelemente)
sind hier bewusst falsch: Sie erzeugen **eigene Berechtigungen pro Objekt** und
brechen damit die Vererbung innerhalb der Site.

Was `Sites.Selected` allein bewirkt: **nichts.** Microsoft sagt es unmissver­
ständlich — eine App mit einer `*.Selected`-Zustimmung „would initially have no
access". Erst der Grant aus Schritt 4 öffnet genau eine Site; er vererbt sich
von dort auf alle Bibliotheken, Ordner und Dateien dieser Site
(„Permissions at the site collection level do not break inheritance").

> ⚠️ **Nach der Zustimmung muss JanuaPort neu starten — sonst kommt weiterhin
> ein 403.** Anwendungsberechtigungen stecken **fest im ausgestellten Token**.
> JanuaPort holt sich den Token selbst und hält ihn im Speicher, bis er kurz vor
> dem Ablauf erneuert wird. Ein Token, der **vor** der Zustimmung ausgestellt
> wurde, kennt sie nicht — und das bis zu **einer Stunde** lang.
>
> Deshalb: nach dem Erteilen **oder Nachtragen** einer Berechtigung das Gateway
> neu starten (z. B. `docker compose restart jnpt`) — oder bis zu eine Stunde
> warten. Beim Mail-Connector war genau das am 06.08.2026 live die Ursache eines
> hartnäckigen 403.

## 5. Schritt 3 — Client Secret in den Vault

```bash
printf '%s' '<client-secret>' | jnpt credential set --name microsoft-graph-sharepoint
```

Das Secret liegt danach verschlüsselt im Vault und ist nicht mehr auslesbar. Es
erscheint in keinem Log, keiner API-Antwort und keiner Fehlermeldung. Der
Access-Token, den JanuaPort sich damit selbst holt, lebt ausschließlich im
Speicher und wird ~60 Sekunden vor Ablauf erneuert.

## 6. Schritt 4 — Die Site freigeben (Site-Grant, Pflicht)

Das ist der Schritt, der aus „diese App darf ausgewählte Sites" ein „diese App
darf genau `https://contoso.sharepoint.com/sites/Belegablage`, und zwar nur
lesen" macht.

**Wer darf ihn ausführen?** Ein Mensch mit Tenant-Admin-Rolle
(SharePoint-Administrator oder höher); die Graph-Berechtigung dafür ist
`Sites.FullControl.All` — laut Microsoft „necessarily high", weil man mit diesem
Aufruf einer App auch Vollzugriff geben könnte. **JanuaPort führt den Grant
nicht selbst aus** und kann es auch nicht: Der Connector hat nur `Sites.Selected`
und die Rolle `read`. Der Handgriff gehört dem Betreiber — genau wie die
Postfach-Grenze beim Mail-Connector.

**Womit?** Am einfachsten im [Graph Explorer](https://developer.microsoft.com/graph/graph-explorer)
(als Admin angemeldet, dort einmalig die Berechtigung `Sites.FullControl.All`
zustimmen) oder per PowerShell mit dem Modul `Microsoft.Graph.Sites`.

### 6.1 Site-ID ermitteln

```http
GET https://graph.microsoft.com/v1.0/sites/contoso.sharepoint.com:/sites/Belegablage
```

Die Antwort enthält die **Site-ID** in der dreiteiligen Form
`contoso.sharepoint.com,<guid>,<guid>`. Diese ID ist der `{siteId}` der nächsten
beiden Aufrufe.

### 6.2 Den Grant setzen — genau dieser Aufruf

```http
POST https://graph.microsoft.com/v1.0/sites/{siteId}/permissions
Content-Type: application/json

{
  "roles": ["read"],
  "grantedToIdentities": [{
    "application": {
      "id": "<client-id-der-app-registrierung>",
      "displayName": "JanuaPort — SharePoint-Lesezugriff"
    }
  }]
}
```

- `"roles": ["read"]` — **lesen, sonst nichts.** Möglich wären auch `write`,
  `owner` und `fullcontrol`; für diesen Connector ist jede davon zu viel.
- `id` ist die **Anwendungs-(Client-)ID** aus Schritt 1, nicht die Objekt-ID.
- Die Antwort ist ein `201 Created` mit einer **Permission-ID** (z. B. `"1"`).
  Notiere sie: Mit ihr wird die Freigabe später wieder entzogen.
- Microsoft markiert im Antwort-Body `grantedToIdentities` als veraltet
  (zugunsten von `grantedToIdentitiesV2`) — im **Request** ist
  `grantedToIdentities` weiterhin die dokumentierte Form.

Dasselbe in PowerShell:

```powershell
Connect-MgGraph -Scopes "Sites.FullControl.All"
$params = @{
  roles = @("read")
  grantedToIdentities = @(@{ application = @{ id = "<client-id>"; displayName = "JanuaPort — SharePoint-Lesezugriff" } })
}
New-MgSitePermission -SiteId "<siteId>" -BodyParameter $params
```

### 6.3 Gegenprobe und Rücknahme

```http
GET    https://graph.microsoft.com/v1.0/sites/{siteId}/permissions
DELETE https://graph.microsoft.com/v1.0/sites/{siteId}/permissions/{permissionId}
```

Die erste Zeile zeigt, welche Apps auf dieser Site etwas dürfen — sie gehört ins
Protokoll der Einrichtung. Die zweite nimmt die Freigabe wieder zurück; danach
antwortet der Connector wieder mit 403, ohne dass jemand ein Secret anfassen
muss. Es gibt damit **zwei** unabhängige Notbremsen: den Grant löschen
(diese Site) oder die Zustimmung in Entra entziehen (alle Sites dieser App).

## 7. Schritt 5 — Spec anpassen, laden, berechtigen

Die ausgelieferte Spec ist eine **Vorlage**: **drei** Werte sind
mandantenspezifisch.

```yaml
auth:
  token_url: https://login.microsoftonline.com/<mandanten-id>/oauth2/v2.0/token
  client_id: "<client-id>"
```

Und die **Site-Adresse** an **zwei** Stellen — im Pfad von `get_site` und im
Pfad von `list_libraries`:

```yaml
    path: "/v1.0/sites/contoso.sharepoint.com:/sites/Belegablage"
    path: "/v1.0/sites/contoso.sharepoint.com:/sites/Belegablage:/drives"
```

Ersetze `contoso.sharepoint.com` durch deinen SharePoint-Host und
`/sites/Belegablage` durch den server-relativen Pfad deiner Site. Der
**abschließende** Doppelpunkt in der zweiten Zeile gehört zur Adressierung und
bleibt stehen. Wer lieber die in Schritt 6.1 ermittelte **Site-ID** einsetzt:
Sie passt an dieselbe Stelle, dann entfällt in `list_libraries` der abschließende
Doppelpunkt (`/v1.0/sites/<siteId>/drives`).

Danach laden — entweder die Datei ins Connector-Verzeichnis legen (Default
`/data/connectors`) oder zur Laufzeit:

```bash
jnpt connector add --file microsoft-graph-sharepoint.yaml
docker compose kill -s HUP jnpt      # laufender Server übernimmt sie ohne Neustart
jnpt connector check microsoft-graph-sharepoint
```

Zum Schluss die Berechtigung **in JanuaPort** (deny-by-default — ohne diese Zeile
sieht ein Agent gar nichts):

```bash
jnpt token allow <token-id> microsoft-graph-sharepoint    # alle vier Lese-Tools
```

Eine zweite Zeile für Schreibrechte gibt es hier nicht: Dieser Connector hat kein
Schreib-Tool.

## 8. Was `jnpt connector check` hier meldet — und was nicht

Anders als beim Mail-Connector laufen hier **alle vier Stufen**: (1) Spec
gültig, (2) **Auth-Werte ausgefüllt** — kein Vorlagen-Platzhalter mehr in
`token_url`/`client_id` (Story #709, siehe Schritt 5 oben), (3) Credential im
Vault, (4) **Probe-Aufruf gegen die echte API** — `get_site` ist parameterlos
und deshalb als `check: true` markiert. Genau dieser Aufruf ist zugleich der
Beleg, dass der Site-Grant greift.

Ohne Credential sieht das so aus (Stufe 4 wird gar nicht erst versucht):

```
Connector "microsoft-graph-sharepoint":
  [ok]   Spec ist gültig (4 Tools)
  [ok]   Auth-Werte sind ausgefüllt (kein Vorlagen-Platzhalter)
  [fail] Credential "microsoft-graph-sharepoint" fehlt im Vault — anlegen mit `jnpt credential set --name microsoft-graph-sharepoint`
```

Wurde Schritt 5 übersprungen (token_url/client_id stehen noch auf der
Null-GUID der Vorlage), scheitert bereits Stufe 2 — mit dem betroffenen Feld
in der Meldung, bevor die Credential-Prüfung überhaupt läuft:

```
Connector "microsoft-graph-sharepoint":
  [ok]   Spec ist gültig (4 Tools)
  [fail] auth.client_id trägt noch den Vorlagen-Platzhalter 00000000-0000-0000-0000-000000000000 — durch die Anwendungs-(Client-)ID der App-Registrierung ersetzen
```

Typische Antworten im Betrieb und was sie bedeuten:

| Symptom | Meist die Ursache |
|---|---|
| „Zielsystem verweigert den Zugriff (HTTP 403) … es fehlt die Berechtigung für diese Ressource" | **Der Site-Grant fehlt oder gilt einer anderen Site** — nicht das Credential. Drei Ursachen in dieser Reihenfolge prüfen: (1) Schritt 4 gar nicht oder für die falsche Site ausgeführt; (2) der Grant existiert, aber JanuaPort hält noch einen Token von **vor** der Zustimmung — **neu starten**; (3) `Sites.Selected` ist in Entra nicht (mehr) zugestimmt. In allen drei Fällen hat die **Anmeldung funktioniert** — das Client Secret ist **nicht** die Ursache |
| HTTP 401 (auch „Token-Endpoint lehnt die Anfrage ab (HTTP 401)") | Der **Token-Bezug** scheitert: `client_id`/`token_url` falsch oder das Client Secret abgelaufen. **Nicht** die fehlende Freigabe — die meldet Graph als 403 |
| HTTP 404 | Die **Site-Adresse** in der Spec stimmt nicht (Tippfehler im Host oder im server-relativen Pfad). Ein 404 ist keine Ablehnung: Die App durfte fragen, es gibt dort nur nichts |
| HTTP 429 | Drosselung durch SharePoint; JanuaPort wiederholt bewusst nicht (siehe §9) |
| „Antwort zu groß" | Eine Seite mit sehr vielen Einträgen — `top` kleiner wählen (JanuaPorts Limit liegt bei 1 MiB je Antwort) |

## 9. Ehrliche Grenzen

- **Kein Datei-Inhalt, kein Download-Link.** Siehe den Kasten in §1. `webUrl` ist
  eine normale SharePoint-URL: Ein Mensch muss sich anmelden, um sie zu öffnen —
  genau der Unterschied zur vorauthentifizierten Download-URL.
- **Kein automatisches Blättern.** Der Agent blättert selbst: `top` setzt die
  Seitengröße, und wenn es mehr gibt, trägt die Antwort `naechste_seite` (Graphs
  eigene Folge-URL). Aus dieser URL nimmt er den Wert von `$skiptoken` und
  reicht ihn als `skiptoken` in den nächsten Aufruf. Eine Seitenzahl oder einen
  Zähler gibt es bei dieser Sammlung nicht.
- **Drosselung: nur `Retry-After` ist verlässlich.** SharePoint sendet **keine**
  `RateLimit-*`-Header (die aktuelle Microsoft-Doku widerspricht darin einem
  älteren Devblog). JanuaPort macht heute **einen** Versuch ohne Rückzug und
  reicht einen 429 als Upstream-Fehler an den Agenten durch; der Connector
  bremst sich vorsorglich auf ~5 Aufrufe/Sekunde. Ein automatischer Rückzug ist
  eine eigene, offene Arbeit (#485).
- **Der Grant vererbt sich — auf die ganze Site.** Wer der App nur *einen Ordner*
  zeigen will, kann das mit diesem Connector nicht: Datei- oder listengenaue
  Freigaben brechen die Vererbung pro Objekt und sind hier bewusst nicht
  vorgesehen. Die saubere Antwort ist eine **eigene Site** für die Ablage, die
  der Agent sehen darf.
- **Eine Bibliothek ist kein Archiv.** Menschen verschieben, umbenennen und
  löschen Dateien; eine Element-ID bleibt dabei stabil, ein Pfad nicht.
- **Kein `privacy:`-Block.** Datei- und Ordnernamen können personenbezogene
  Daten tragen („Kündigung_Mustermann.pdf"). Welche Felder pseudonymisiert
  gehören, ist eine eigene fachliche Bewertung (#328) und ausdrücklich nicht
  Teil dieses Connectors.

## 10. Live-Beleg — die Checkliste für „fertig"

Diese Anleitung ist gegen die offizielle Microsoft-Doku geschrieben. **Gebaut ist
nicht belegt:** Der Connector gilt erst als fertig, wenn er einmal gegen einen
echten Mandanten gelaufen ist und das im Issue steht (#551).

- [ ] `jnpt connector check microsoft-graph-sharepoint` — alle vier Stufen `ok`
      (Stufe 4 ist `get_site` mit **HTTP 200** gegen die gegrantete Site).
- [ ] **Gegenprobe:** derselbe Aufruf gegen eine **nicht** gegrantete Site
      (Spec-Kopie mit anderer Site-Adresse) muss **403** liefern — nicht 200 und
      nicht 404. Erst diese Richtung beweist, dass die Grenze wirkt.
- [ ] `list_libraries` liefert die Bibliothek(en) der Site.
- [ ] `list_children` mit `folder_id: root` liefert den Inhalt der obersten
      Ebene, `list_children` mit einer Ordner-ID die Ebene darunter.
- [ ] **Sichtprüfung der Antworten:** nirgends ein `downloadUrl`, nirgends ein
      Link, der ohne Anmeldung funktioniert.
- [ ] Zwei Punkte, die nur der Live-Lauf klären kann, und die deshalb ausdrücklich
      mitprotokolliert werden:
      **(a)** ob `folder_id: root` — die reservierte Kennung der
      Bibliothekswurzel — an der Stelle `/drives/{id}/items/root/children`
      akzeptiert wird (die Doku führt die Wurzel als eigene Beziehung
      `/drives/{id}/root/children` auf; die Kennung `root` an der Element-Stelle
      ist gängige Praxis, steht dort aber nicht). Falls Graph sie ablehnt, ist
      die Nachbesserung klein: ein eigenes Wurzel-Werkzeug;
      **(b)** ob Bibliotheks-IDs mit `!` (Form `b!…`) in der URL-kodierten Form
      (`b%21…`), die JanuaPort sendet, angenommen werden.
- [ ] Ein echter Agenten-Rundlauf (Claude/Cowork) über einen berechtigten Token:
      „welche Dateien liegen in der Ablage" muss ohne Umweg beantwortbar sein.
