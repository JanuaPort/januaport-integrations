# Microsoft-365-Postfach anbinden (Connector `microsoft-graph-mail`)

Betreiber-Anleitung für den Graph-Connector aus
`connector-specs/microsoft-graph-mail.yaml` (Story #332, PO-Entscheid #329).
Zielgruppe: wer den Mandanten verwaltet und JanuaPort betreibt. Programmierkenntnisse
sind nicht nötig, ein Exchange-Online-Admin-Zugang schon.

## 1. Was der Connector kann — und was er ausdrücklich nicht kann

**Fünf Werkzeuge, mehr nicht:**

| Tool | Was es tut | Art |
|---|---|---|
| `microsoft_graph_mail_list_messages` | Nachrichten **eines** Postfachs auflisten, gefiltert nach Zeitraum, Absender oder Betreff | lesend |
| `microsoft_graph_mail_get_message` | **eine** Nachricht samt Text holen | lesend |
| `microsoft_graph_mail_list_attachments` | die Anhänge **einer** Nachricht auflisten (nur Name, Typ, Größe — nie die Datei) | lesend |
| `microsoft_graph_mail_read_attachment` | den **Textinhalt** genau eines Anhangs holen | lesend |
| `microsoft_graph_mail_create_draft` | eine Mail als **Entwurf** ins Postfach legen | **schreibend** |

**Es gibt kein Sende-Tool — auch kein „vorbereitetes".** JanuaPort schreibt den
Entwurf, ein Mensch öffnet ihn in Outlook, prüft ihn und klickt auf Senden. Das
ist eine Produktentscheidung und zugleich technisch abgesichert: Die Anwendung
bekommt **kein** `Mail.Send`. Microsoft schreibt zur Rolle
`Application Mail.ReadWrite` ausdrücklich: *„Doesn't include permission to send
mail."* Ein Agent kann über diesen Weg also nicht senden, selbst wenn er es
wollte.

**Anhänge: die KI bekommt den INHALT als Text, nie die Datei.** Der typische
Fall ist die Eingangsrechnung als PDF-Anhang. `list_attachments` zeigt, was an
einer Nachricht hängt; `read_attachment` liefert den Text genau eines Anhangs —
bei einer E-Rechnung (ZUGFeRD/Factur-X) zusätzlich das eingebettete XML, das für
eine KI die belastbare Quelle für Beträge und Rechnungsnummern ist. Es gibt
**keinen Download und keinen Link**: Die Bytes bleiben im Gateway und erreichen
weder eine Platte noch das Audit-Log. Was das kann und was nicht, steht ehrlich
in §9. **Dafür braucht es keine neue Berechtigung** — `Mail.Read` genügt, und
davon ist das ohnehin vergebene `Mail.ReadWrite` die Obermenge.

**Ebenfalls nicht dabei** (bewusste Grenzen dieser Version): Dateien an einen
Entwurf **anhängen**, Anhänge als Datei **herunterladen** (an der KI vorbei —
s. aber `save_attachment` gleich unten, das genau das serverseitig tut), OCR
für gescannte PDFs, Kalender, SharePoint/OneDrive, Teams, automatisches
Durchblättern aller Seiten.

### Ein sechstes Werkzeug, nicht aus dieser Datei: `save_attachment`

Neben den fünf Werkzeugen dieser YAML-Spec gibt es ein **sechstes**,
`microsoft-graph-mail_save_attachment` (Story #718) — es steht bewusst **nicht**
in dieser Datei, weil es kein deklaratives YAML-Werkzeug ist, sondern ein
**Go-natives** Werkzeug (Präzedenz: Kartei, Use-Case-Katalog, mitgeliefertes
Wissen). Der Grund: Ein Schreib-Tool verlangt laut Format `POST`, der
Byte-Abruf eines Anhangs bei Graph ist aber technisch ein `GET` — Tool-Semantik
(Schreiben) und HTTP-Methode (Lesen) laufen hier auseinander, und das Format
lässt das bewusst nicht zu.

`save_attachment(mailbox, message_id, attachment_id, ziel, dateiname)` legt
**einen** Anhang serverseitig — ohne dass die KI die Bytes je zu sehen bekommt —
in einer **Ablage** ab (`type: ablage`, siehe `docs/file-connector-spec.md`;
der historische Typ `write_target` lädt seit Story #729 als Alias derselben
Ablage-Art). Die KI wählt `ziel` (den Namen der Ablage) und **nur den
Namensstamm** von `dateiname` — die tatsächliche Dateiendung setzt JanuaPort
selbst, abgeleitet aus dem von Graph gemeldeten Inhaltstyp des Anhangs, nie
aus der Eingabe der KI. Grund: Die Ablage ist üblicherweise eine
Windows-Freigabe im Kundennetz, und eine frei gewählte Endung hieße, dass eine
eingehende Mail dort ein `.ps1`/`.exe` platzieren lassen könnte.

Wie `create_draft` ist es ein **Schreib**-Werkzeug: ein Mensch muss es
bestätigen, und es braucht den **tool-genauen** Scope
`microsoft-graph-mail:save_attachment` — ein Scope auf die ganze Integration
deckt es nicht (Schritt 5 unten). Es rührt das Postfach nicht an (nichts wird
gelöscht, verschoben oder als gelesen markiert) und wertet den Inhalt nicht aus
(kein OCR, keine Klassifikation, kein Umbenennen nach Rechnungsinhalt — das tut
die KI weiterhin über `read_attachment`). Ein Anhang je Aufruf, nur
`fileAttachment` (kein `isInline`, kein `itemAttachment`/`referenceAttachment`).

⚠️ **Seit Story #729 prüft `save_attachment` zusätzlich ein ZWEITES Recht:
`<ziel>:write_file` auf der Ziel-Ablage** — nach der Auflösung von `ziel`,
VOR jedem Abruf bei Graph. Das ist dasselbe Recht, das auch das
`write_file`-Werkzeug DIESER Ablage selbst verlangt (Epic-Regel 3, #725):
`ziel` kann heute **jede** Ablage sein, für die der rufende Token dieses
Recht hat — nicht mehr nur eine eigens dafür deklarierte Integration. Fehlt
das Recht (oder sind die Rechte des Tokens nicht ladbar — fail-closed), wird
der Aufruf abgelehnt, BEVOR Graph kontaktiert wird; die Meldung nennt den
Integrationsnamen (`ziel`, Eingabe der KI), nie einen Verzeichnispfad. Ein
Token braucht also ZWEI Scopes, um erfolgreich abzulegen:
`microsoft-graph-mail:save_attachment` (den Aufruf selbst) UND
`<ziel>:write_file` (das Ablegen-Recht auf die Ziel-Ablage) — zwei
unabhängige Berechtigungs-Achsen, keine implizite Ableitung der einen aus
der anderen.

**Welche Postfächer kommen als Ziel infrage?** Alle drei Werkzeuge sprechen das
Postfach über `/users/{smtp-adresse}/messages` an. Daraus folgt, welche Form
sich eignet und welche nicht:

- **Freigegebenes Postfach (Shared Mailbox): ja.** Es ist ein regulärer
  Postfach-Träger, wird über seine SMTP-Adresse angesprochen und kostet keine
  Lizenz. Das ist die Form, auf die dieser Connector zielt.
- **Microsoft-365-Gruppen-Postfach: nein.** Eine Gruppe ist kein Benutzerobjekt;
  ihre Unterhaltungen liegen in Graph unter `/groups/{id}/conversations` und
  brauchen eine eigene Familie von Berechtigungen. Dieser Connector erreicht sie
  nicht — und soll es in dieser Version auch nicht.
- **Verteilerliste: nein.** Sie verteilt Nachrichten nur weiter, sie hat selbst
  gar kein Postfach.

> ⚠️ **Nicht verwechseln:** Die **E-Mail-aktivierte Sicherheitsgruppe**, die in
> Variante B von Schritt 4 vorkommt, ist etwas anderes als ein
> Gruppen-Postfach. Sie ist dort nur der **Behälter**, über den die Richtlinie
> sagt, *welche* Postfächer erlaubt sind — nie selbst das Ziel-Postfach. Die
> Begriffe ähneln sich, gemeint sind zwei verschiedene Dinge.

## 2. Die Einrichtung in fünf Schritten

1. App-Registrierung in Microsoft Entra ID anlegen
2. Berechtigung `Mail.ReadWrite` (Anwendung) erteilen
3. Client Secret in den JanuaPort-Vault legen
4. **Zugriff in Exchange Online auf genau ein Postfach begrenzen**
5. Spec anpassen, laden und in JanuaPort berechtigen

> ⚠️ **Schritt 4 ist keine Feinheit, sondern die eigentliche
> Sicherheitsmaßnahme.** Eine Microsoft-365-App-Berechtigung gilt von sich aus
> **mandantenweit — für ALLE Postfächer**. Ohne Schritt 4 dürfte dieser
> Connector jedes Postfach der Organisation lesen und beschreiben. **Ohne diesen
> Schritt ist die Einrichtung nicht fertig.**

## 3. Schritt 1 — App-Registrierung

Im [Microsoft Entra Admin Center](https://entra.microsoft.com) →
**App-Registrierungen** → **Neue Registrierung**:

- Name z. B. `JanuaPort — Postfachzugriff` (der Name taucht später in Protokollen auf).
- Kontotypen: **nur Konten in diesem Organisationsverzeichnis**.
- Redirect-URI: **keine**. Dieser Zugriff läuft app-only, es gibt keinen
  Anmeldedialog und keine an eine menschliche Sitzung gebundene Sitzung.

Notiere aus der Übersicht:

- **Anwendungs-(Client-)ID** → kommt in die Spec (`auth.client_id`, kein Secret).
- **Verzeichnis-(Mandanten-)ID** → kommt in die Spec (in die `auth.token_url`).

Dann **Zertifikate & Geheimnisse** → **Neuer geheimer Clientschlüssel**. Der Wert
ist **nur einmal** sichtbar; er geht in Schritt 3 direkt in den Vault und
**nirgendwo sonst hin** (keine Datei, kein Ticket, keine Chat-Nachricht). Notiere
dir das **Ablaufdatum** — an dem Tag steht der Connector still, bis ein neues
Secret im Vault liegt.

## 4. Schritt 2 — Berechtigung und Admin-Consent

**API-Berechtigungen** → **Berechtigung hinzufügen** → **Microsoft Graph** →
**Anwendungsberechtigungen** → `Mail.ReadWrite` → danach **Administratorzustimmung
erteilen**.

Eine Berechtigung genügt: `Mail.ReadWrite` schließt das Lesen ein. `Mail.Read`
zusätzlich zu erteilen bringt nichts und macht das Bild im Portal nur unklarer.
`Mail.Send` wird **nicht** erteilt.

Das gilt auch für die **Anhänge**: Das Auflisten und das Lesen eines Anhangs
brauchen laut Microsoft-Doku app-only `Mail.Read` — davon ist `Mail.ReadWrite`
die Obermenge. **Kein neuer Consent, kein zusätzlicher Handgriff im Portal.**

> ⚠️ **Nach der Zustimmung muss JanuaPort neu starten — sonst kommt weiterhin
> ein 403.** Anwendungsberechtigungen stecken **fest im ausgestellten Token**.
> JanuaPort holt sich den Token selbst und hält ihn im Speicher, bis er kurz vor
> dem Ablauf erneuert wird (Schritt 3). Ein Token, der **vor** der Zustimmung
> ausgestellt wurde, kennt sie deshalb nicht — und das bis zu **einer Stunde**
> lang. Wer in dieser Zeit ein Tool aufruft, bekommt einen Fehler und sucht in
> Entra nach einer Ursache, die dort längst behoben ist.
>
> Deshalb: nach dem Erteilen **oder Nachtragen** einer Berechtigung das Gateway
> neu starten (z. B. `docker compose restart jnpt`) — oder bis zu eine Stunde
> warten. Am 06.08.2026 live beobachtet: Erst der Neustart hat geholfen.

> ⚠️ **Ehrlich zur Berechtigung — das gehört hierher und nicht nur ins Issue:**
> `Mail.ReadWrite` ist **gröber als die Werkzeugfläche dieses Connectors**.
> Microsoft kennt keine Berechtigung „darf nur Entwürfe anlegen"; in Graph
> erlaubt `Mail.ReadWrite` auch, Mails zu ändern und zu löschen. Wer die
> App-Registrierung im Portal ansieht, sieht also mehr, als JanuaPort je tut — und
> soll davon nicht überrascht werden.
>
> Verengt wird an zwei anderen Stellen:
>
> * **In JanuaPort** auf genau die drei Tools oben: Deny-by-default, ein Token bekommt
>   nur, was ihm ausdrücklich erlaubt wurde, das Schreib-Tool zusätzlich nur über
>   einen **tool-genauen** Scope — und jeder Aufruf steht im Audit-Log.
> * **In Exchange** auf genau ein Postfach (Schritt 4).
>
> Das ist genau die Arbeitsteilung, für die es dieses Produkt gibt: Die
> Plattform gibt nur grobe Schalter her, die feine Begrenzung und die
> Nachvollziehbarkeit liefert das Gateway.

Wenn du in Schritt 4 den **RBAC-Weg (Variante A)** gehst, lies dort zuerst den
Kasten „Vereinigung statt Schnittmenge" — dann wird diese Zustimmung
**absichtlich nicht** erteilt bzw. wieder entzogen.

## 5. Schritt 3 — Client Secret in den Vault

```bash
printf '%s' '<client-secret>' | jnpt credential set --name microsoft-graph-mail
```

Das Secret liegt danach verschlüsselt im Vault und ist nicht mehr auslesbar. Es
erscheint in keinem Log, keiner API-Antwort und keiner Fehlermeldung — auch dann
nicht, wenn Microsoft es in einem Fehlertext zurückspiegeln würde. Der
Access-Token, den JanuaPort sich damit selbst holt, lebt ausschließlich im Speicher
und wird ~60 Sekunden vor Ablauf erneuert.

## 6. Schritt 4 — Zugriff auf **ein** Postfach begrenzen (Pflicht)

Das ist der Schritt, der aus „diese App darf alle Postfächer" ein „diese App darf
genau `rechnungen@example.com`" macht. Es gibt zwei Wege. **Genau einer von
beiden muss eingerichtet sein.**

Beide brauchen die Exchange-Online-PowerShell:

```powershell
Connect-ExchangeOnline
```

### Variante A (Microsofts aktueller Weg): RBAC for Applications

Microsoft ersetzt die alten Application Access Policies durch **RBAC for
Applications** und schreibt zur alten Variante ausdrücklich: *„Don't create new
App Access Policies as these policies will eventually require migration to Role
Based Access Control for Applications."* Für eine **neue** Einrichtung ist
Variante A deshalb der richtige Weg.

```powershell
# 1. Zeiger auf den Dienstprinzipal der App anlegen.
#    ACHTUNG: AppId und ObjectId kommen aus "Unternehmensanwendungen"
#    (Enterprise Applications), NICHT aus der Seite "App-Registrierungen".
New-ServicePrincipal -AppId <client-id> -ObjectId <objekt-id-der-unternehmensanwendung> -DisplayName "JanuaPort Postfachzugriff"

# 2. Ressourcen-Scope: genau ein Postfach.
New-ManagementScope -Name "JanuaPort Pilotpostfach" -RecipientRestrictionFilter "PrimarySmtpAddress -eq 'rechnungen@example.com'"

# 3. Rolle mit genau diesem Scope zuweisen.
New-ManagementRoleAssignment -App <objekt-id-der-unternehmensanwendung> -Role "Application Mail.ReadWrite" -CustomResourceScope "JanuaPort Pilotpostfach"

# 4. Gegenprobe — InScope muss für das erlaubte Postfach True und für jedes
#    andere False sein.
Test-ServicePrincipalAuthorization -Identity <objekt-id-der-unternehmensanwendung> -Resource rechnungen@example.com | Format-Table
Test-ServicePrincipalAuthorization -Identity <objekt-id-der-unternehmensanwendung> -Resource irgendwer@example.com   | Format-Table
```

> ⚠️ **Vereinigung statt Schnittmenge — die Falle dieser Variante.**
> Berechtigungen aus Entra ID und aus Exchange-RBAC **addieren sich**. Microsoft
> sagt das unmissverständlich: Bleibt `Mail.ReadWrite` zusätzlich mandantenweit
> in Entra zugestimmt, ist die Postfach-Begrenzung **wirkungslos**. Bei
> Variante A gilt deshalb: die Administratorzustimmung aus Schritt 2 für
> `Mail.ReadWrite` **entziehen** (oder gar nicht erst erteilen) — die
> Berechtigung kommt dann ausschließlich aus Exchange.

### Variante B (klassisch): Application Access Policy

Der Weg, den die Story ursprünglich benennt. Er funktioniert weiterhin und
begrenzt genau die in **Entra** erteilte Zustimmung — Schritt 2 bleibt also wie
beschrieben. Microsoft rät aber von **neuen** Policies ab (siehe oben); wer
Variante B wählt, sollte die spätere Umstellung einplanen.

```powershell
# 1. Eine E-Mail-aktivierte Sicherheitsgruppe, die genau das Postfach enthält.
New-DistributionGroup -Name "JanuaPort Postfach-Freigabe" -Alias jnpt-postfach -Type Security
Add-DistributionGroupMember -Identity jnpt-postfach -Member rechnungen@example.com

# 2. Die App auf die Mitglieder dieser Gruppe beschränken.
#    RestrictAccess = "nur diese", nicht "alle außer diesen".
New-ApplicationAccessPolicy -AppId <client-id> -PolicyScopeGroupId jnpt-postfach@example.com -AccessRight RestrictAccess -Description "JanuaPort darf nur das Rechnungs-Postfach."

# 3. Gegenprobe für beide Richtungen.
Test-ApplicationAccessPolicy -Identity rechnungen@example.com -AppId <client-id>
Test-ApplicationAccessPolicy -Identity irgendwer@example.com   -AppId <client-id>
```

Ein **freigegebenes Postfach** (Shared Mailbox) kann nicht direkt als
`PolicyScopeGroupId` dienen — es muss Mitglied einer E-Mail-aktivierten
Sicherheitsgruppe sein (siehe Schritt 1 oben). Diese Gruppe ist ausschließlich
der Behälter für die Richtlinie — Ziel-Postfach der Werkzeuge bleibt die Shared
Mailbox selbst.

### Für beide Varianten

- **Rechne mit Verzögerung.** Änderungen an App-Berechtigungen greifen laut
  Microsoft je nach Aktivität der App zwischen **30 Minuten und 2 Stunden**. Die
  `Test-…`-Cmdlets umgehen diesen Cache — der echte Aufruf nicht. Ein
  „funktioniert noch nicht" direkt nach der Einrichtung ist deshalb kein Beweis.
- **Beide Varianten gleichzeitig für dieselbe Berechtigung sind ein Fehler** —
  siehe den Kasten oben.
- Die Gegenprobe („ein fremdes Postfach wird abgelehnt") gehört ins Protokoll der
  Einrichtung. Ein Zugriff auf ein nicht freigegebenes Postfach endet in JanuaPort als
  Upstream-Fehler mit HTTP 403.

## 7. Schritt 5 — Spec anpassen, laden, berechtigen

Die ausgelieferte Spec ist eine **Vorlage**: Zwei Werte sind mandantenspezifisch
und stehen dort als Null-GUID.

```yaml
auth:
  token_url: https://login.microsoftonline.com/<mandanten-id>/oauth2/v2.0/token
  client_id: "<client-id>"
```

Danach laden — entweder die Datei ins Connector-Verzeichnis legen (Default
`/data/connectors`) oder zur Laufzeit:

```bash
jnpt connector add --file microsoft-graph-mail.yaml
docker compose kill -s HUP jnpt      # laufender Server übernimmt sie ohne Neustart
jnpt connector check microsoft-graph-mail
```

Zum Schluss die Berechtigung **in JanuaPort** (deny-by-default — ohne diese Zeilen
sieht ein Agent gar nichts):

```bash
jnpt token allow <token-id> microsoft-graph-mail                     # die vier Lese-Tools
jnpt token allow <token-id> microsoft-graph-mail:create_draft        # der Entwurfs-Weg, EXTRA
jnpt token allow <token-id> microsoft-graph-mail:save_attachment     # die Ablage, EXTRA (Story #718)
jnpt token allow <token-id> eingang-rechnungen:write_file            # das Ablegen-Recht AUF DER ZIEL-ABLAGE (Story #729)
```

Die zweite und dritte Zeile sind kein Versehen: **Ein integrationsweiter Scope
erfasst Schreib-Tools nie.** „Gib dem Token das Postfach" vergibt damit nie
versehentlich das Anlegen von Entwürfen oder das Ablegen von Anhängen — beides
muss ausdrücklich erteilt werden (in der Admin-Oberfläche entsprechend über den
eigenen Schalter für Schreibrechte). Die VIERTE Zeile ist seit Story #729
zusätzlich nötig: `save_attachment` braucht eine konfigurierte Ziel-Ablage
(`type: ablage`, `docs/file-connector-spec.md`) UND das Recht
`<ziel>:write_file` auf genau dieser Ablage — ohne beides lehnt das Werkzeug
jeden Aufruf mit einer klaren, pfadfreien Meldung ab, statt irgendwo zu
schreiben oder Graph überhaupt zu kontaktieren.

## 8. Was `jnpt connector check` hier meldet — und was nicht

`jnpt connector check microsoft-graph-mail` prüft (1) die Spec, (2) ob
`token_url`/`client_id` noch die Vorlagen-Platzhalter tragen (Story #709 — vor
dem Einsatz durch die Werte der eigenen App-Registrierung ersetzen, siehe der
Kommentarkopf in `connector-specs/microsoft-graph-mail.yaml`) und (3) ob das
Credential im Vault liegt. **Stufe 4 (Probe-Aufruf gegen die echte API) entfällt
für diesen Connector**, und `jnpt connector selftest` überspringt ihn: Jedes Tool
braucht den Parameter `mailbox`, und die Probe ruft nur parameterlose Tools auf.
Das ist Absicht — die Postfachadresse gehört dem Betreiber und nicht in eine
eingecheckte Spec.

Der erste echte Beweis ist deshalb ein echter Tool-Aufruf über einen Agenten oder
die Admin-Oberfläche. Typische Antworten und was sie bedeuten:

| Symptom | Meist die Ursache |
|---|---|
| Konfigurationsfehler beim Token-Bezug | `client_id`/`token_url` in der Spec falsch, oder das Client Secret im Vault ist abgelaufen |
| „Zielsystem verweigert den Zugriff (HTTP 403) … es fehlt die Berechtigung für diese Ressource" | Drei Ursachen, in dieser Reihenfolge prüfen: (1) die Berechtigung ist erteilt, aber JanuaPort hält noch den davor ausgestellten Token — **Neustart**, siehe den Kasten in Schritt 2; (2) Schritt 4: Postfach nicht im erlaubten Scope; (3) die Änderung ist noch nicht durchgeschlagen (30 min–2 h). In allen drei Fällen hat die Anmeldung funktioniert — das Client Secret ist **nicht** die Ursache |
| HTTP 401 (auch als „Token-Endpoint lehnt die Anfrage ab (HTTP 401)") | Der **Token-Bezug** scheitert: `client_id`/`token_url` falsch oder das Client Secret abgelaufen — dieselbe Ecke wie in der ersten Zeile. **Nicht** die fehlende Zustimmung; die meldet Graph als 403 |
| HTTP 429 | Drosselung durch Microsoft; JanuaPort wiederholt bewusst nicht |
| Antwort zu groß | eine sehr große Nachricht — JanuaPorts Limit liegt bei 1 MiB je Antwort |

## 9. Ehrliche Grenzen

- **Nachrichten-Text: Klartext wird gebeten, nicht garantiert.** Graph liefert
  Bodies in HTML, solange man nicht den Header
  `Prefer: outlook.body-content-type="text"` mitschickt. Seit #347 kann das
  Format statische Request-Header, und `get_message` sendet ihn. **Im Lauf vom
  07.08.2026 hat Graph die Bitte auch angewandt:** `body.contentType` kam als
  `text` zurück, der Inhalt ohne HTML-Auszeichnung. Aus dieser Beobachtung wird
  aber keine Zusage — `Prefer` ist laut HTTP eine **Bitte**: Der Dienst darf sie
  übergehen (und vermerkt eine angewandte Präferenz ggf. im Antwort-Header
  `Preference-Applied`, den JanuaPort nicht auswertet). Ein Agent liest deshalb
  weiterhin `body.contentType` in der Antwort, statt Klartext anzunehmen. Für die
  Liste ist das ohne Bedeutung (laut Doku liefert „List messages" Bodies derzeit
  nur als HTML); `bodyPreview` ist immer Klartext.
- **Filtern: entweder OData oder Volltext, nicht beides.** Der
  Nachrichten-Endpunkt unterstützt `$filter` und `$search` nicht in einem
  Aufruf. Die Tool-Beschreibungen sagen das dem Agenten und nennen für beide
  Wege die Muster für Zeitraum, Absender und Betreff.
- **Kein automatisches Blättern.** Der Agent blättert über `top`/`skip` bzw.
  besser über einen enger gezogenen Zeitraum. Microsoft warnt selbst davor, sich
  auf `skip` zu verlassen: Die Zahl zählt alle durchlaufenen Elemente des
  Postfachs, nicht nur die gelieferten Nachrichten.
- **Anhänge: Text, keine Datei — und das mit klaren Grenzen.** Die KI bekommt
  nie die Bytes und nie einen Download-Link, sondern den daraus gewonnenen Text.
  ⚠️ **Seit Story #728 ist das dieselbe Ergebnisform wie `read_file` auf einer
  Ablage** (`type: ablage`, `docs/file-connector-spec.md`) — derselbe Extraktor
  (#703/#707), über die geteilte Fähigkeit `internal/filetext`, mit demselben
  prozessweiten Zeit-/Nebenläufigkeits-Deckel (ein Kontingent von zwei
  gleichzeitigen Extraktionen, geteilt zwischen BEIDEN Werkzeugen). Konkret:
  - **Gelesen werden** die Textebene eines PDF, das in einer E-Rechnung
    (ZUGFeRD/Factur-X) eingebettete XML, sowie XML, Text, CSV und JSON, wie sie
    sind.
  - **Nicht gelesen werden** Word, Excel, Bilder, `.eml` und ZIP. Sie kommen mit
    Typ und Größe zurück und der ausdrücklichen Auskunft, dass der Inhalt nicht
    zu lesen ist — damit kein Agent ihn rät.
  - **Ein gescanntes PDF hat keine Textebene.** Dann kommt leerer Text plus eine
    Notiz, die das sagt. **Es gibt kein OCR** in dieser Version.
  - **Ein verschlüsseltes PDF wird nicht gelesen.** Das gilt auch für Dateien,
    die sich ohne Passwort öffnen lassen — viele Rechnungsprogramme
    verschlüsseln, um Bearbeitung zu verhindern, obwohl ein Mensch den Inhalt
    ohne Nachfrage sehen kann. Die Antwort kommt mit leerem Text und einer
    Notiz, die die Verschlüsselung ehrlich benennt (kein Passwort-Raten, keine
    Entschlüsselung — Scope-Grenze `internal/extract`). Unterstützt wird nur
    Verschlüsselungsversion V ≤ 4; ein modern verschlüsseltes PDF (V=5,
    AES-256) fällt in dieselbe Notiz.
  - **PDF-Text bewahrt die Wörter, nicht das Layout.** Mehrspaltige Rechnungen
    können verweben, Tabellen verlieren ihre Struktur, und bei ungewöhnlichen
    Schriften werden Umlaute zu Ersatzzeichen. Das reicht für „was steht in
    dieser Rechnung", nicht für „lies die Positionszeilen exakt aus". Bei einer
    E-Rechnung ist das zweitrangig — dort steht die Wahrheit im XML.
  - **Nicht jeder Anhang ist eine Datei.** Ein *itemAttachment* ist ein
    eingebettetes Outlook-Element (es kommt als unaufbereitete MIME-Nachricht),
    ein *referenceAttachment* ist nur ein **Link** auf eine Cloud-Datei und
    endet mit HTTP 405. Beides steht in der Liste als `type`, damit der Agent es
    vorher sieht.
  - **Deckel:** höchstens 10 MiB je Anhang (eine größere Datei wird abgelehnt,
    nicht halb gelesen), höchstens 128 KiB Text je Antwort (darüber gekürzt, mit
    ehrlicher Markierung), höchstens 500 Seiten und 5 eingebettete Dateien,
    höchstens 20 Sekunden Auswertung. **Höchstens zwei Extraktionen
    PROZESSWEIT gleichzeitig** (#707) — und dieses Kontingent teilt sich diese
    Integration seit #728 mit JEDER Ablage, die `read_file` liest: Ein dritter
    gleichzeitiger Aufruf (gleich über welchen der beiden Wege) wird sofort mit
    „gerade zu viele Datei-Auswertungen" abgewiesen, statt zu warten. **Ein
    Anhang je Aufruf** — es gibt keinen Sammel-Abruf über alle Mails.
  - **Die Bytes berühren nichts.** Kein Dateisystem, kein Log, kein Audit, keine
    Fehlermeldung. Im Audit steht, WELCHER Anhang gelesen wurde, nie WAS darin
    stand.
  - **Kein Anhängen.** Ein Entwurf bekommt weiterhin keine Datei mit.
  - **`save_attachment` ist der bewusste Gegenpol zu alledem** (Story #718,
    s. o.): Es reicht die Bytes serverseitig weiter, statt Text daraus zu
    gewinnen — und genau deshalb parst und wertet es nichts aus (keine der
    Speicherbomben-Klasse aus #707/#715 trifft diesen Weg). Im Audit-Protokoll
    stehen Dateiname, Postfach, Nachricht/Anhang-ID und Ziel-Ablage bewusst im
    **Klartext** (nicht `[REDACTED]`) — die Datei liegt nach dem Aufruf ohnehin
    genau so benannt im Ordner des Kunden, und ein geschwärzter Dateiname im
    Protokoll schützte dort niemanden mehr.
- **Das Postfach ist kein Archiv.** Nachrichten können jederzeit von Menschen
  verschoben oder gelöscht werden; die Liste umfasst alle Ordner (auch Gelöschte
  Objekte und Entwürfe), solange man nicht einschränkt.
- **Kein `privacy:`-Block.** Ein Postfach führt personenbezogene Daten. Welche
  Felder pseudonymisiert gehören, ist eine eigene fachliche Bewertung (#328) und
  ausdrücklich nicht Teil dieses Connectors. Im **Audit** wird lediglich der
  Entwurfstext (`content`) nicht mitgeschrieben — Postfach, Empfänger und Betreff
  bleiben sichtbar, damit ein Schreibvorgang zurechenbar bleibt.

## 10. Was nur live zu klären ist

Diese Anleitung ist überwiegend gegen die offizielle Microsoft-Doku geschrieben.
Der Live-Lauf gegen einen echten Mandanten (**#344**, 06./07.08.2026) hat einen
Teil davon bestätigt; was er nicht berührt hat, bleibt hier offen benannt:

- ob der App-only-Token unter **Variante A** auch **ohne** jede Entra-Zustimmung
  ausgestellt wird (die Exchange-Doku beschreibt den Fall so, die
  Token-Ausstellung liegt aber bei Entra) — falls nicht, ist Variante B der Weg;
  der Live-Lauf lief mit erteilter Entra-Zustimmung und beantwortet die Frage
  deshalb nicht;
- die exakten Drosselungsgrenzen des Outlook-Dienstes (auf der aktuellen
  Throttling-Seite nicht auffindbar); der Connector bremst sich vorsorglich auf
  ~5 Aufrufe/Sekunde;
- ob Message-IDs mit einem `/` in der URL-kodierten Form, die JanuaPort sendet,
  von Graph angenommen werden. **Teilweise beantwortet:** Die im Lauf verwendete
  ID trug `-` und `=` und wurde anstandslos angenommen; ein `/` kam in der
  Stichprobe nicht vor.
- **(#703, offen) Ob Graph das feste `$select` auf der Anhangs-Sammlung
  wirklich beachtet.** Die Doku sagt ja; beobachtet ist es noch nicht. Wird es
  ignoriert, liefert Graph `contentBytes` — die vollständige base64-Nutzlast
  jedes Anhangs — ungefragt mit, und eine Nachricht mit mehreren PDFs reißt das
  1-MiB-Antwortlimit. Das ist der erste Prüfpunkt des Live-Belegs am echten
  Postfach.
- **(#703, offen) Wie gut die Textausbeute bei echten Lieferantenrechnungen
  ist.** Gegen synthetische Fixtures ist sie belegt; wie viele reale PDFs eine
  brauchbare Textebene haben (statt Scan zu sein) und wie stark die Lesereihen-
  folge bei mehrspaltigen Layouts leidet, sagt erst der Lauf gegen echte Post.
- **(#718, offen) `save_attachment` gegen die echte API.** Gegen Stubs/Fixtures
  belegt: Byte-Abruf über dieselbe Sicherheitskette wie `read_attachment`,
  Endungs-Ableitung aus dem Content-Type, Rückwandlung, Kollisionsschutz. Ein
  Live-Lauf am Pilotpostfach müsste zusätzlich zeigen: (a) dass der von Graph
  auf `/$value` tatsächlich gemeldete `Content-Type` für ein reales
  PDF-Anhang-Attachment die erwartete Endung `.pdf` ergibt (die Fixtures setzen
  den Header selbst und beweisen die Ableitungs-LOGIK, nicht Graphs
  Antwortverhalten); (b) dass die Datei mit korrekten Rechten (`0600`) auf der
  tatsächlichen Ziel-Freigabe ankommt — inklusive der Chmod-Frage aus dem
  #716-Fund (BOX: auf CIFS ist `fchmod` ein wirkungsloser No-Op); (c) die
  Postfach-Gegenprobe (nach dem Aufruf ist die Nachricht unverändert: nicht
  gelesen, nicht verschoben).

## Beilage: fertiges Skript für Schritt 4 (Variante A)

[`examples/exchange-postfach-grenze.ps1`](../examples/exchange-postfach-grenze.ps1)
— drei Werte eintragen, ausführen, im Browser anmelden. Enthält die im
Praxis-Lauf (13.08.2026) gefundenen Stolpersteine: `-AllowClobber` bei der
Modul-Installation (Anaconda-Rechner), die Objekt-ID kommt aus den
**Unternehmensanwendungen**, und nach dem Lauf ist das Entfernen der
Entra-`Mail.ReadWrite`-Zustimmung Pflicht (Rechte addieren sich). Wirkung:
30 Minuten bis 2 Stunden; die Anlage danach einmal neu starten (Token-Cache).

> ⚠️ **Schritt 0 in frischen Tenants: `Enable-OrganizationCustomization`.** Ohne
> die einmalige Organisations-Freischaltung lehnt Exchange eigene Scopes und
> Rollenzuweisungen mit „derzeit nicht zulässig" ab — jeder Tenant, der nie etwas
> in Exchange angepasst hat, hängt genau hier (live gefunden 13.08.2026). Die
> Beilage macht den Schritt automatisch mit. Zweite Lehre aus demselben Lauf:
> Exchange-Cmdlets werfen **weiche** Fehler an `try/catch` vorbei — Skripte
> brauchen `-ErrorAction Stop`, sonst wird Scheitern als Erfolg gemeldet.
