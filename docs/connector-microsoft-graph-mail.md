# Microsoft-365-Postfach anbinden (Connector `microsoft-graph-mail`)

Betreiber-Anleitung für den Graph-Connector aus
`connector-specs/microsoft-graph-mail.yaml` (Story #332, PO-Entscheid #329).
Zielgruppe: wer den Mandanten verwaltet und JanuaPort betreibt. Programmierkenntnisse
sind nicht nötig, ein Exchange-Online-Admin-Zugang schon.

## 1. Was der Connector kann — und was er ausdrücklich nicht kann

**Sieben Werkzeuge in der Datei, dazu drei Go-native weiter unten:**

| Tool | Was es tut | Art |
|---|---|---|
| `microsoft_graph_mail_list_messages` | Nachrichten **eines** Postfachs auflisten, gefiltert nach Zeitraum, Absender oder Betreff | lesend |
| `microsoft_graph_mail_get_message` | **eine** Nachricht samt Text holen | lesend |
| `microsoft_graph_mail_list_attachments` | die Anhänge **einer** Nachricht auflisten (nur Name, Typ, Größe — nie die Datei) | lesend |
| `microsoft_graph_mail_read_attachment` | den **Textinhalt** genau eines Anhangs holen | lesend |
| `microsoft_graph_mail_create_draft` | eine Mail als **Entwurf** ins Postfach legen | **schreibend** |
| `microsoft_graph_mail_reply` | **eine** vorhandene Nachricht beantworten, nur an deren Absender (seit 3.0.0, **Opt-in**, siehe Abschnitt 11) | **schreibend, sendet** |
| `microsoft_graph_mail_send_mail` | eine **neue** Mail an eine frei wählbare Adresse senden, optional mit einer Kopie, ohne Tagesdeckel (seit 4.0.0, **Opt-in**, siehe Abschnitt 12) | **schreibend, sendet** |

**Gesendet wird nur über zwei Werkzeuge, und nur als Opt-in.** `create_draft` sendet nichts: JanuaPort
schreibt den Entwurf, ein Mensch öffnet ihn in Outlook, prüft ihn und klickt auf Senden.
Die Werkzeuge, die senden, sind `reply` (Abschnitt 11) und `send_mail` (Abschnitt 12).
`reply` beantwortet **eine** vorhandene Nachricht, nur an deren Absender, ohne weitere
Empfänger, ohne Anhänge, ohne Weiterleiten. `send_mail` sendet **eine neue Mail** an eine
frei wählbare Adresse, ohne Tagesdeckel und ohne Freigabeklick (PO-Entscheid 21.11.2026);
auch dort gibt es keine Anhänge, kein BCC und kein HTML. Es gibt kein `reply_all`. Beide
laufen nur, wenn der Admin sie bei der Werkzeugauswahl wählt, ein Token das tool-genaue
Recht trägt und Exchange der App die Rolle `Application Mail.Send` mit einem eigenen
Bereich nur auf das Sende-Postfach gegeben hat. Eine App ohne diese Rolle kann nicht senden: Microsoft
schreibt zur Rolle `Application Mail.ReadWrite` ausdrücklich *„Doesn't include permission
to send mail."* Die Graph-API-Berechtigung `Mail.Send` wird **nie** erteilt.

**Senden an feste Empfänger gibt es als eigenen, schmalen Weg:** Für feste Empfänger,
festen Betreff und ein festes Postfach gibt es das Sende-Werkzeug `send_alert` einer
installationsgebundenen Vorlage, mit eigener App und eigenem Credential; diese
Vorlage und ihre App bleiben davon unberührt, siehe
(Produkt-Doku, nicht öffentlich).

**Bestätigung (heute, Fassung 2.0.2):** Alle Schreibwerkzeuge dieser
Integration (`create_draft`, seit 3.0.0 `reply`, seit 4.0.0 `send_mail` und die drei Go-nativen unten) sagen der KI
dasselbe: Sie sind als Schreibvorgang annotiert, der Client kann deshalb
nachfragen, JanuaPort selbst fragt nie, und sie brauchen das tool-genaue
Recht. Der frühere Satz „a human must confirm it … do not call it
autonomously" ist weg — ein produktiver Agent wartete sonst auf eine
Bestätigung, die nie kommt. Eine bestehende Mail-Integration ist eine Kopie der
Vorlage und behält den alten `create_draft`-Text, bis sie auf 2.0.2 angehoben
wird; die drei Go-nativen Werkzeuge sprechen sofort den neuen Text.

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
aus der Eingabe der KI. Meldet Graph einen nicht gelisteten Typ — Outlook
deklariert Anhänge gern als `application/octet-stream` —, erkennt JanuaPort den
Inhalt und vergibt die Endung aus derselben Erlaubtliste: ein PDF wird
`.pdf`, ebenso PNG, JPEG, GIF; Text wird `.txt`, Unbekanntes `.bin`. Der
Original-Dateiname des Absenders bestimmt die Endung nie (ein `x.pdf` mit
Text-Inhalt wird nicht `.pdf`). **docx/xlsx** sind ZIP-Container und bleiben
`.bin`, wenn Graph sie nicht als Word/Excel deklariert — bewusst, die Endung
wird nicht aus dem Container-Inhalt geraten. Grund: Die Ablage ist üblicherweise eine
Windows-Freigabe im Kundennetz, und eine frei gewählte Endung hieße, dass eine
eingehende Mail dort ein `.ps1`/`.exe` platzieren lassen könnte.

Wie `create_draft` ist es ein **Schreib**-Werkzeug: Es ist als solches
annotiert (der Client kann nachfragen, JanuaPort selbst fragt nie), und
es braucht den **tool-genauen** Scope
`microsoft-graph-mail:save_attachment` — ein Scope auf die ganze Integration
deckt es nicht (Schritt 5 unten). Es rührt das Postfach nicht an (nichts wird
gelöscht, verschoben oder als gelesen markiert — dafür gibt es
das eigene Werkzeug `move_message`, s. u.) und wertet den Inhalt nicht aus
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

⚠️ **Heute:** Ein Anhang aus einem pseudonymisierten Postfach landet nur
in einer pseudonymisierten Ablage. Gilt für `read_attachment` eine
wirksame Deklaration (im Spec-Default, integrationsweit oder am Werkzeug —
die **effektive** Deklaration, Hauptschalter inklusive), lehnt
`save_attachment` jede Ziel-Ablage ab, die selbst nicht pseudonymisiert ist
— sonst holte `get_file`/`read_file` den Anhang dort im Klartext ab. Warum
gerade `read_attachment`: Es ist das einzige Werkzeug dieser Integration, das
Anhang-**Inhalt** an die KI gibt; seine Deklaration ist die Aussage des
Betreibers über Anhänge. Eine Deklaration nur auf `list_messages` (Absender,
Betreff) betrifft Metadaten und zählt hier bewusst nicht. Die Prüfung läuft
nach der Ziel-Prüfung und **vor** dem Abruf bei Graph; die Meldung sagt ehrlich,
warum (ohne Dateinamen), das Audit trägt `denied`. Ist eine der beiden
Deklarationen nicht lesbar, wird nichts abgerufen und nichts abgelegt
(Konfigurationsfehler).

⚠️ **Heute:** Gefährliche Anhänge werden abgewiesen, nicht abgelegt. Jeder
Anhang läuft durch dieselbe Namens- und Inhaltsprüfung wie `write_file`. Der
Grund: Eine Datei in der Ablage (SMB, Share) trägt keine Internet-Markierung,
Office öffnet sie ohne geschützte Ansicht, und „Makros aus dem Internet
blockieren" greift nicht. Derselbe Anhang, direkt in Outlook geöffnet, bekäme
die Markierung. Abgewiesen werden:

- Anhänge mit **ausführbarem Programmcode** (PE, ELF, Mach-O) — auch wenn der
  Absender sie als `application/pdf` deklariert;
- **docx/xlsx mit Makros** (VBA-Projekt) oder mit einer **externen Beziehung**
  (nachgeladene Vorlage `attachedTemplate`, verknüpftes Objekt; Hyperlinks
  bleiben erlaubt);
- **alte Office-Formate und andere CFB-Container:** alte `.doc`/`.xls`,
  **passwortgeschützte** docx/xlsx und **angehängte Outlook-Nachrichten**
  (`.msg`, z. B. eine „als Anlage weitergeleitete“ Rechnung). `save_attachment`
  vergibt für sie die Endung `.bin` (`.doc`/`.xls` stehen heute nicht mehr
  in der Endungstabelle), der Inhalt wird trotzdem als CFB erkannt;
- ein **Namensstamm**, der eine Namensregel verletzt (unsichtbare Format- oder
  Bidi-Zeichen wie U+202E, `: * ? " < > |`, Windows-Gerätenamen).

Die Absage ist ein Argumentfehler (Audit `argument_error`), in der Ablage liegt
danach nichts. Die Meldung nennt den gesendeten Namensstamm, nie den Inhalt.
**Was der Betreiber tut:** Ein Mensch öffnet die Mail in Outlook und legt den
Anhang selbst ab (dort mit Internet-Markierung). Ein erneuter Aufruf mit
anderem `dateiname` hilft nicht.

### Ein siebtes Werkzeug, ebenfalls nicht aus dieser Datei: `move_message`

`microsoft-graph-mail_move_message` ist das zweite **Go-native**
Werkzeug an dieser Integration — aus demselben Grund wie `save_attachment`
nicht in dieser YAML: Der Lesestatus einer Nachricht ist bei Graph ein
`PATCH`, und das Spec-Format kennt bewusst nur `GET` und `POST`.

`move_message(mailbox, message_id, folder, mark_unread=true)` verschiebt
**eine** Nachricht in einen anderen Ordner **desselben** Postfachs und
markiert sie dabei als **ungelesen**. Das ist der Weg für Unklares
(PO-Entscheid 16.09.2026): Die Mail landet im Ordner „Unklar"
und leuchtet dort als neu auf — ein Mensch sieht sie, ohne dass irgendetwas
weitergeleitet wurde.

**Der Ordner wird über seinen Anzeigenamen benannt** („Unklar"), nie über eine
Graph-ID: Die KI kennt keine IDs, und den Ordner hat ein Mensch angelegt.
**Voraussetzung: Der Ordner existiert.** Dieses Werkzeug legt keine Ordner an
— gibt es ihn nicht, endet der Aufruf mit genau dieser Begründung, und am
Postfach ändert sich nichts. Gesucht wird er auf der **obersten Ebene** des
Postfachs und anschließend unter den **Unterordnern des Posteingangs**; liegt
er tiefer verschachtelt, findet dieses Werkzeug ihn nicht (bewusste Grenze,
s. §9).

Wie `create_draft` und `save_attachment` ist es ein **Schreib**-Werkzeug: Es
ist als solches annotiert (der Client kann nachfragen, JanuaPort selbst fragt
nie), und es braucht den **tool-genauen** Scope
`microsoft-graph-mail:move_message` — ein Scope auf die ganze Integration
deckt es nicht (Schritt 5 unten). Ein zweites Recht wie bei `save_attachment`
gibt es nicht: Es wird nichts in eine andere Integration geschrieben.

**Was es ausdrücklich nicht tut:** kein Weiterleiten, kein Senden, kein
Löschen, kein Anlegen von Ordnern, kein Verschieben in ein **anderes**
Postfach (strukturell unmöglich — die Exchange-Beschränkung aus Schritt 4 gilt
weiterhin für jeden Aufruf), keine Sammelaktion („verschiebe alle, die …" ist
die Entscheidung der KI, Nachricht für Nachricht).

⚠️ **Die Nachrichten-ID ändert sich nur, wenn der Ordner wechselt** (Graph-Verhalten,
nicht unsere Entscheidung; live belegt). Beim Verschieben in einen
**anderen** Ordner vergibt Graph eine **neue** ID, die alte antwortet danach mit 404.
Beim Verschieben in den Ordner, in dem die Nachricht schon liegt, bleibt die ID gleich.
Deshalb gibt `move_message` die ID zurück:

- **Die Antwort trägt `message_id`** mit der aktuell gültigen ID, und der Text nennt
  beide („bisher … jetzt …, die bisherige gilt nicht mehr"). Die KI nimmt für jeden
  Folgeschritt (Anhang ablegen, als gelesen markieren, Entwurf) die ID aus
  `message_id`.
- **Blieb die ID gleich**, sagt der Text, dass sie unverändert gilt, und behauptet
  keine neue. `message_id` trägt dann die gleiche, weiter gültige ID.
- **Liefert Graph keine brauchbare `id`** (sie fehlt, ist leer oder kein String), ist
  das Verschieben trotzdem erfolgt: Die Antwort meldet Erfolg **ohne** `message_id`,
  mit dem Hinweis „Wechselt der Ordner, vergibt Graph eine neue Nachrichten-ID; die
  aktuelle liefert list_messages." Es gibt keinen Fehler und keinen zweiten
  Graph-Aufruf.
- **Die Werkzeug-Beschreibung** sagt der KI dasselbe: Die bisherige ID ist nach einem
  Ordnerwechsel ungültig, die Antwort trägt die aktuelle.

**Im Protokoll stehen Postfach, Nachrichten-IDs und Ordnername — nie Betreff, Absender
oder Text.** Die neue ID steht im Detail des bestehenden Audit-Ereignisses (ein
Selektor; kein zusätzliches Ereignis). Graph antwortet auf das Verschieben mit der
vollständigen Nachricht, aber **nur das Feld `id` betritt den Prozess**: Der
Move-Request deklariert die Antwort-Projektion `{id: id}`, alles andere (Betreff,
Absender, Text, Vorschau) wird gar nicht erst gelesen und erscheint weder in der
Antwort noch im Audit noch im Log. Die Antwort auf das Setzen des Lesestatus wird
weiterhin überhaupt nicht gelesen.

### Ein achtes Werkzeug, ebenfalls nicht aus dieser Datei: `mark_read`

`microsoft-graph-mail_mark_read` ist das dritte **Go-native**
Werkzeug an dieser Integration, aus demselben Grund wie `move_message`: Der
Lesestatus ist bei Graph ein `PATCH`, und das Spec-Format kennt nur `GET` und
`POST`.

`mark_read(mailbox, message_id)` markiert **eine** Nachricht als **gelesen**,
**ohne sie zu verschieben**. Sie bleibt in ihrem Ordner und behält ihre
Nachrichten-ID. Dafür sendet JanuaPort genau einen Request:
`PATCH /v1.0/users/{mailbox}/messages/{id}` mit dem festen Inhalt
`{"isRead": true}`.

**Abgrenzung zu `move_message`:** Wer eine Nachricht in einen anderen Ordner
legen will (optional als ungelesen, damit ein Mensch sie dort als neu sieht),
nimmt `move_message`. Wer nur festhalten will, dass eine Nachricht bearbeitet
ist, nimmt `mark_read`. Als **ungelesen** markieren kann nur `move_message`
(`mark_unread`); `mark_read` hat dafür keinen Schalter. Beide
Werkzeug-Beschreibungen sagen das der KI.

**Recht:** Es ist ein **Schreib**-Werkzeug. Es ist als solches annotiert (der
Client kann nachfragen, JanuaPort selbst fragt nie), und es braucht den
**tool-genauen** Scope `microsoft-graph-mail:mark_read`; ein
Scope auf die ganze Integration deckt es nicht (Schritt 5 unten). In Microsoft
365 braucht es **keine neue Berechtigung**: `Mail.ReadWrite` ist schon
vergeben, und die Postfach-Grenze aus Schritt 4 gilt unverändert.

**Was es ausdrücklich nicht tut:** nicht verschieben, nicht löschen, nicht
senden, keine weiteren Eigenschaften (Markierung, Kategorien, Wichtigkeit),
keine Sammelaktion.

**Im Protokoll stehen Postfach und Nachrichten-ID, nie Betreff, Absender oder
Text.** Graph antwortet auf das `PATCH` mit der vollständigen Nachricht;
JanuaPort liest diese Antwort gar nicht erst ein. Die KI
bekommt nur eine Bestätigung. Ist die ID unbekannt (HTTP 404, etwa weil die
Nachricht vorher mit `move_message` verschoben wurde und dabei eine neue ID
bekam; die neue steht in der Antwort von `move_message`, Feld `message_id`), sagt die
Meldung, dass `list_messages` die aktuelle ID liefert.

**Welche Postfächer kommen als Ziel infrage?** Die Postfach-Werkzeuge sprechen das
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

Das Antworten auf Mails (`reply`) ist **kein** sechster Pflichtschritt, sondern ein
eigenes Opt-in mit eigener Sende-Grenze: Abschnitt 11. Dort steht auch, was **vor** der
Einrichtung zu entscheiden ist (ein eigenes Anfrage-Postfach).

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
Die Graph-API-Berechtigung `Mail.Send` wird **nicht** erteilt. Für `reply` gibt es
`Mail.Send` nur als Exchange-Rolle mit eigenem Bereich (Abschnitt 11, Schritt 11.2).

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
> * **In JanuaPort** auf die neun beschriebenen Werkzeuge: Deny-by-default, ein Token bekommt
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
jnpt token allow <token-id> microsoft-graph-mail:move_message # das Verschieben, EXTRA
jnpt token allow <token-id> microsoft-graph-mail:mark_read # als gelesen markieren, EXTRA
jnpt token allow <token-id> eingang-rechnungen:write_file            # das Ablegen-Recht AUF DER ZIEL-ABLAGE (Story #729)
```

Die zweite bis fünfte Zeile sind kein Versehen: **Ein integrationsweiter Scope
erfasst Schreib-Tools nie.** „Gib dem Token das Postfach" vergibt damit nie
versehentlich das Anlegen von Entwürfen, das Ablegen von Anhängen, das
Verschieben von Nachrichten oder das Setzen des Lesestatus — alle vier müssen ausdrücklich erteilt werden (in der Admin-Oberfläche entsprechend über den
eigenen Schalter für Schreibrechte). Die SECHSTE Zeile ist
zusätzlich nötig: `save_attachment` braucht eine konfigurierte Ziel-Ablage
(`type: ablage`, `docs/file-connector-spec.md`) UND das Recht
`<ziel>:write_file` auf genau dieser Ablage — ohne beides lehnt das Werkzeug
jeden Aufruf mit einer klaren, pfadfreien Meldung ab, statt irgendwo zu
schreiben oder Graph überhaupt zu kontaktieren.

**`reply` steht bewusst nicht in dieser Liste.** Das Antworten ist ein eigenes Opt-in mit
eigener Sende-Grenze in Exchange (Abschnitt 11); das Recht
`microsoft-graph-mail:reply` wird erst dort vergeben, und ein Scope auf die ganze
Integration erfasst es nicht.

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
  über die geteilte Fähigkeit zur Textextraktion (Produkt-Doku, nicht öffentlich), mit demselben
  prozessweiten Zeit-/Nebenläufigkeits-Deckel (ein Kontingent von zwei
  gleichzeitigen Extraktionen, geteilt zwischen BEIDEN Werkzeugen). Konkret:
  - **Gelesen werden** die Textebene eines PDF, das in einer E-Rechnung
    (ZUGFeRD/Factur-X) eingebettete XML, sowie XML, Text, CSV und JSON, wie sie
    sind.
  - **Auch Word, Excel und PowerPoint** (`docx`, `xlsx`, `pptx`,
    `kind` entsprechend): Word als Absätze, Excel Blatt für Blatt
    (`## Blatt: <Name>`, Zellen durch Tab, Zahlen roh, Datumswerte als
    Excel-Seriennummer), PowerPoint Folie für Folie (`## Folie N`). Erkannt
    am Inhalt, nicht am `contentType` des Absenders; gedeckelt gegen
    Zip-Bomben (Einzelheiten und Grenzen: `docs/file-connector-spec.md`,
    „Office lesen"). Der Text läuft durch dieselbe Pseudonymisierung wie
    PDF-Text. Gelesen, nie ausgeführt: Makros, eingebettete Objekte und
    Formeln werden nicht angefasst.
  - **Nicht gelesen werden** alte Office-Dateien (`.doc`, `.xls`, `.ppt`),
    passwortgeschützte Office-Dateien, Bilder, `.eml` und ZIP. Sie kommen mit
    Typ und Größe zurück und der ausdrücklichen Auskunft, dass der Inhalt nicht
    zu lesen ist — damit kein Agent ihn rät.
  - **Die Vorlage steht dafür auf Fassung 2.0.1** (nur die Beschreibung von
    `read_attachment`). ⚠️ Eine bestehende Mail-Integration ist eine KOPIE der
    Vorlage in der Datenbank und behält den alten Text („Word, Excel … nicht
    lesbar"), bis der Betreiber sie auf 2.0.1 anhebt. Gelesen wird Office
    trotzdem sofort — der alte Text verspricht nur weniger, als das Werkzeug
    kann.
  - **Ein gescanntes PDF hat keine Textebene.** Dann kommt leerer Text plus eine
    Notiz, die das sagt. **Es gibt kein OCR** in dieser Version.
  - **Ein verschlüsseltes PDF wird nicht gelesen.** Das gilt auch für Dateien,
    die sich ohne Passwort öffnen lassen — viele Rechnungsprogramme
    verschlüsseln, um Bearbeitung zu verhindern, obwohl ein Mensch den Inhalt
    ohne Nachfrage sehen kann. Die Antwort kommt mit leerem Text und einer
    Notiz, die die Verschlüsselung ehrlich benennt (kein Passwort-Raten, keine
    Entschlüsselung — Scope-Grenze (Produkt-Doku, nicht öffentlich)). Unterstützt wird nur
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
- **`move_message` findet einen Ordner auf zwei Ebenen, nicht überall**
. Gesucht wird der Anzeigename auf der **obersten Ebene** des
  Postfachs und unter den **direkten Unterordnern des Posteingangs** — das
  sind die beiden Stellen, an denen ein Mensch „Unklar" üblicherweise anlegt.
  Ein tiefer verschachtelter Ordner („Posteingang → 2026 → Unklar") wird nicht
  gefunden; der Aufruf endet dann mit „gibt es nicht", und am Postfach ändert
  sich nichts. Graph kennt keine Ordner-Suche über alle Ebenen in einem
  Aufruf, und ein Durchlaufen des ganzen Ordnerbaums wäre teuer und
  unberechenbar. Zwei gleichnamige Ordner auf derselben Ebene werden
  abgelehnt statt geraten. Und: **Nur beim Wechsel in einen anderen Ordner vergibt Graph eine neue
  Nachrichten-ID** — die vorherige ist dann ungültig. Im selben Ordner bleibt
  sie unverändert; die gültige ID steht in `message_id`.
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
  Endungs-Ableitung aus dem Content-Type (heute bei octet-stream aus dem
  erkannten Inhalt), Rückwandlung, Kollisionsschutz. Ein
  Live-Lauf am Pilotpostfach müsste zusätzlich zeigen: (a) dass der von Graph
  auf `/$value` tatsächlich gemeldete `Content-Type` für ein reales
  PDF-Anhang-Attachment die erwartete Endung `.pdf` ergibt (die Fixtures setzen
  den Header selbst und beweisen die Ableitungs-LOGIK, nicht Graphs
  Antwortverhalten); (b) dass die Datei mit korrekten Rechten (`0600`) auf der
  tatsächlichen Ziel-Freigabe ankommt — inklusive der Chmod-Frage aus dem
  #716-Fund (BOX: auf CIFS ist `fchmod` ein wirkungsloser No-Op); (c) die
  Postfach-Gegenprobe (nach dem Aufruf ist die Nachricht unverändert: nicht
  gelesen, nicht verschoben).
- **`move_message` gegen die echte API — LIVE BELEGT 23.09.2026**
  (Showcase 0.61.0, Postfach der Ein-Postfach-Grenze, Testordner
  `Posteingang/Test` und `Root-Test` auf oberster Ebene; Tabelle im Issue).
  Vorher gegen einen Fake-Graph belegt: die drei Requests in fester Reihenfolge
  samt Pfaden, `$filter` und JSON-Bodys, der Ordner-Wächter, die Ablehnung ohne
  Namenstreffer, kein Graph-Fremdtext in der Antwort. Live bestätigt:
  (a) der Anzeigenamen-Filter greift auf beiden Wegen — Unterordner des
  Posteingangs **und** Ordner der obersten Ebene wurden gefunden;
  (b) erneutes Verschieben in den Ordner, in dem die Nachricht schon liegt, ist
  ein Erfolg, kein Fehler; (c) die Nachricht erscheint im Zielordner als
  ungelesen; (d) **Graph vergibt beim Ordnerwechsel eine neue Nachrichten-ID** —
  die alte ID antwortet danach mit **404**; (e) Audit: je Aufruf ein
  Write-Ereignis ohne Betreff und ohne Inhalt. Nachrichten-ID und Ordnername
  stehen im Audit, weil beide Argumente sind und `move_message` kein Argument
  redigiert (`addMailMoveMessageToMeta`, Test
  `TestAddMailMoveMessageToMetaTraegtWriteUndKeinenInhalt`) — live abgelesen
  wurde die Listenansicht, nicht das Detail.
  **Mitbelegt: die fail-safe-Reihenfolge.** Ein Aufruf mit veralteter ID
  scheiterte schon beim Setzen des Lesestatus und meldete „… wurde NICHT
  verschoben" — nichts wurde verändert.
  ⚠️ **Fußangel für Agenten (zum Zeitpunkt des Belegs; behoben heute):** Die
  Erfolgsmeldung nannte damals die **eingegebene** ID, wer mit ihr
  weiterarbeitete, bekam 404. Heute trägt die Antwort die neue ID im Feld
  `message_id`; der **Live-Nachbeleg** (neue ID aus der Antwort → `get_message`
  200) steht noch aus.
- **`mark_read` gegen die echte API — LIVE BELEGT 07.10.2026**
  (Showcase 0.72.0, Postfach der Ein-Postfach-Grenze, Wegwerf-Token mit
  `microsoft-graph-mail`, `:mark_read` und `:move_message`). Vorher gegen einen
  Fake-Graph belegt: genau ein `PATCH …/messages/{id}` mit
  `Content-Type: application/json` und dem Body `{"isRead":true}`, keine
  Nachrichten-Inhalte in Antwort und Audit, 401/403/404 unterscheidbar. Live
  bestätigt: (a) eine gelesene Nachricht wurde per `move_message`
  (`mark_unread=true`) in ihrem eigenen Ordner auf ungelesen gesetzt und stand
  danach im Filter `isRead eq false`; (b) `mark_read` → Erfolg, derselbe Filter
  zeigt sie nicht mehr, Ordner und ID unverändert; (c) ein zweiter Aufruf ist
  idempotent; (d) eine wohlgeformte, unbekannte ID → **404** mit dem Hinweis auf
  `list_messages`, eine formal ungültige ID → **400**, jeweils „es wurde nichts
  verändert"; (e) Audit: `mark_read` als Write **ohne** Write-ahead-Absicht,
  `move_message` als Absicht plus Ergebnis, in keinem Ereignis Betreff,
  Text oder Absender.
  `list_messages` projiziert `isRead` nicht, deshalb läuft die Gegenprobe über
  den Filter.
- **(offen) `reply` gegen die echte API.** Gegen einen Fake-Graph belegt:
  `POST …/messages/{id}/reply` mit dem Body `{"comment": …}` und nichts sonst, die
  Message-ID als ein Pfadsegment, Graphs 202 ohne Body als Erfolg. Live zu belegen
  (Probelauf in Abschnitt 11.5): (a) dass Graph die Antwort bei gesetztem `replyTo`
  wirklich an `replyTo` adressiert und sonst an `from`; (b) die Antwort in „Gesendete
  Elemente" mit dem Wortlaut des `comment`; (c) die Gegenprobe 403 aus Abschnitt 11.2
  gegen ein lesbares, aber nicht beantwortbares und gegen ein fremdes Postfach nach
  der Wirkzeit; (d) dass die Rolle `Application Mail.Send` allein für das Antworten
  genügt und keine weitere Berechtigung nötig ist.
  ⚠️ **Befund nebenbei:** Beim Verschieben in den Ordner, in dem die Nachricht
  schon liegt, vergibt Graph **keine** neue ID. Der damalige Erfolgstext von
  `move_message` behauptete das trotzdem; heute sagt der Text in
  diesem Fall, dass die ID unverändert gilt.

## 11. Antworten (Opt-in): das Werkzeug `reply`

Seit Fassung **3.0.0** gibt es einen Sendeweg, der an
die vorhandene Mail gebunden ist: `reply` beantwortet **eine** vorhandene Nachricht,
**nur an deren Absender**, ohne `reply_all`, ohne Weiterleiten, ohne Anhänge und ohne
frei wählbare Empfänger. Für eine neue Mail an eine frei gewählte Adresse gibt es seit
4.0.0 das eigene Werkzeug `send_mail` (Abschnitt 12). Alle anderen Werkzeuge dieser
Vorlage senden nichts. Standard ist **aus**: `reply` läuft nur, wenn ein Admin es
ausdrücklich wählt (11.3) und ein Token das tool-genaue Recht trägt.

Wohin Graph die Antwort adressiert, entscheidet die Nachricht: Ist `replyTo` gesetzt,
geht sie an `replyTo`, sonst an `from`. `get_message` zeigt beides (`from`,
`replyTo`, dazu `ccRecipients`). Der Werkzeugtext nennt das als Tatsache und sagt
dazu: Weicht die Domain von `replyTo` von der Domain von `from` ab und ist `from` kein
bekanntes Formular- oder Portal-Postfach des Betreibers, ist `create_draft` der
Weg — ein Mensch prüft den Entwurf und sendet. Der Kern bricht bei abweichendem
`replyTo` **nicht** ab: Kontaktformulare und Buchungsportale senden von einer
noreply-Adresse mit `replyTo` auf die anfragende Person, ein Abbruch legte den
Hauptfall lahm.

### 11.1 Zuerst: ein eigenes Anfrage-Postfach und ein enges Token

**Das gehört vor die Einrichtung.** Der größere Schaden ist nicht die Adresse, sondern
der **Inhalt**: Ein Fremder fragt nach „meinen Terminen", und die KI antwortet mit
Daten aus anderen Mails desselben Postfachs. Verhindern kann das kein Werkzeug, die
Verantwortung liegt beim Betreiber. Zwei Empfehlungen machen es klein:

1. **Ein eigenes Anfrage-Postfach**, in dem nur Anfragen von außen liegen — kein
   Postfach mit Rechnungen, Verträgen oder interner Post. Dazu eine eigene Integration
   mit eigener App-Registrierung und eigenem Credential (Schritt 1 bis 3), deren
   Exchange-Bereiche **nur** dieses Postfach umfassen.
2. **Ein Token, das nur dieses Postfach liest und nur antwortet:** tool-genau
   `list_messages`, `get_message` und `reply` und nichts darüber hinaus (kein
   `create_draft`, kein `save_attachment`, kein `move_message`, solange der Ablauf sie
   nicht braucht). Die Postfach-Grenze selbst liegt allein in Exchange (11.2), weil
   `mailbox` ein Parameter ist, den die KI wählt.

### 11.2 Die Sende-Grenze in Exchange: eigener Bereich, nicht der des Lesens

`Mail.Send` gibt es hier **nur als Exchange-Rolle** `Application Mail.Send` über
**RBAC for Applications**, mit einem **eigenen Management Scope** allein auf das
Anfrage-Postfach — **nie derselbe Scope wie fürs Lesen**. Viele Betreiber haben die
Leserolle auf mehrere Postfächer gelegt; teilte sich das Senden diesen Bereich, dürfte
die App aus jedem dieser Postfächer antworten. Es gilt: **keine Graph-API-Berechtigung
`Mail.Send`.** Sie gälte für alle Postfächer des Mandanten, und
Rechte aus Entra und Exchange addieren sich.

```powershell
# Zusätzlich zur Leserolle aus Schritt 4: eigener Bereich nur für das Antworten.
# <objekt-id> = Objekt-ID der UNTERNEHMENSANWENDUNG (nicht der App-Registrierung).
New-ManagementScope -Name "JanuaPort Antwort-Scope" -RecipientRestrictionFilter "PrimarySmtpAddress -eq 'anfragen@example.com'"
New-ManagementRoleAssignment -App <objekt-id> -Role "Application Mail.Send" -CustomResourceScope "JanuaPort Antwort-Scope"
```

Ein eigenes Skript gibt es dafür nicht; die Befehle sind die aus
[`examples/exchange-postfach-grenze.ps1`](../examples/exchange-postfach-grenze.ps1), mit
der Rolle `Application Mail.Send` und einem zweiten, eigenen Scope.

**Die API-Berechtigungen der App ansehen** (Entra → App-Registrierung →
API-Berechtigungen): Dort darf **keine** Graph-Berechtigung `Mail.Send` stehen. Was dort
steht, gehört in den **Abnahmeprotokoll der Einrichtung** (nur die Namen der Berechtigungen, keine Werte).

**Gegenprobe nach der Wirkzeit, mit Uhrzeit.** Die Richtlinie wirkt erst nach 30 Minuten
bis 2 Stunden (Schritt 4, „Für beide Varianten"). Die Proben laufen **danach** und werden
mit der **Uhrzeit** festgehalten; im Abnahmeprotokoll steht nur die Klasse der Antwort:

| Probe | Erwartung |
|---|---|
| `reply` gegen ein Postfach, das die App **lesen darf, aber nicht beantworten soll** | **403** |
| danach `reply` gegen ein **fremdes** Postfach | **403** |

Gibt es nur ein lesbares Postfach, reicht die zweite Zeile. Die Proben verwenden eine
**Testmail von einer eigenen Testadresse**, die vorher in das jeweilige Postfach gelegt
wurde: Hielte die Grenze nicht, ginge die Antwort an die eigene Testadresse und nicht an
einen echten Absender. Bei **202** statt 403: nicht weitermachen, die Rolle und die
Entra-Zustimmung prüfen. Ein 403 allein belegt die Grenze nicht, es zeigt nur, dass dieser
Aufruf abgelehnt wurde — deshalb beide Proben.

### 11.3 Opt-in: `reply` gezielt wählen, das Recht tool-genau vergeben

- **Neuanlage in der GUI:** Die GUI wählt `reply` nicht vor; der Admin hakt es
  ausdrücklich an. REST und Admin-MCP verlangen ohnehin eine ausdrückliche Werkzeugliste.
- **Anhebung einer vorhandenen Integration:** `jnpt connector upgrade <name> --werkzeug reply --yes`
  (REST und Admin-MCP: `add_tools`). Ohne diese Angabe wird das neue Werkzeug nur
  gemeldet. `--mit-neuen-werkzeugen` übernimmt dagegen **alle** neuen Werkzeuge der Vorlage.
- **⚠️ `jnpt connector add --file`** übernimmt **alle Werkzeuge der Datei**, also auch
  `reply` und `send_mail`. Wer die Datei der Vorlage unverändert lädt und eines der beiden
  nicht will, entfernt den Block `- name: reply` bzw. `- name: send_mail` vorher.
- **Das Recht ist tool-genau:** `jnpt token allow <token-id> microsoft-graph-mail:reply`
  (bei einer Integration mit anderem Namen deren Name). Ein Scope auf die ganze Integration
  erfasst `reply` nicht, und das Recht auf `reply` öffnet auch `create_draft` nicht.

### 11.4 Der Ablauf des Betreibers

Welche Absender Formulare und Portale sind, weiß nur der Betreiber. Er nennt seine
**Formular- und Portal-Absender** (die Postfächer, von denen Kontaktformular,
Buchungsportal und ähnliche Dienste senden) im **Prompt bzw. im Ablauf** der KI. Für jede
andere Mail, bei der die Domain von `replyTo` und von `from` abweicht, nimmt die KI
`create_draft`. Automatische Antworten (Abwesenheit, Zustellberichte) sind keine
Anfragen und werden nicht beantwortet. Höchstens **10 Antworten je UTC-Tag**; ein weiterer
Aufruf wird bis zum nächsten UTC-Tag abgewiesen.

### 11.5 Probelauf: ohne `dry_run`, in zwei Schritten

`reply` hat **kein `dry_run`** (bewusste Ausnahme; sie steht im Kopf der Vorlage).
Der Probelauf nach jeder neuen Fassung:

1. **Der trockene Pfad:** `get_message` auf einer **Testmail**. Es zeigt `from`, `replyTo`
   und `ccRecipients`, also den Empfänger, an den Graph adressieren wird.
2. **Eine echte Antwort** auf diese Testmail, gesendet aus einem **eigenen Testpostfach**
   an das Anfrage-Postfach. Erwartet: das Ergebnis `{"status": 202}`, ein Audit-Eintrag mit
   Status `ok` ohne Text, und die Antwort in **„Gesendete Elemente"** des Anfrage-Postfachs
   — mit dem gesendeten Wortlaut und dem Empfänger. Eine zweite Testmail mit gesetztem
   `replyTo` (Outlook: „Antworten an") belegt, dass die Antwort wirklich an `replyTo` geht
   und nicht an `from`.

### 11.6 Ehrliche Grenzen

- **Das Audit hat den Wortlaut nicht.** `comment` ist geschwärzt (`redact_params`); den
  Wortlaut und die tatsächliche Empfängeradresse belegen allein „Gesendete Elemente".
  Postfach und Nachrichten-ID stehen im Audit.
- **`replyTo` bestimmt der Absender der Mail.** Wer eine Mail schreibt, legt über `replyTo`
  den Empfänger der Antwort fest, und `replyTo` prüft weder SPF noch DMARC. Begrenzt wird
  das durch den Deckel von 10 je Tag, durch das Urteil der KI und durch den Ablauf (11.4),
  nicht durch den Kern. Ging eine Antwort an eine Adresse, die nicht angefragt hat, bitte
  melden: Das ist der Auslöser, eine Prüfung in den Kern zu holen.
- **Der Inhalt** der Antwort kommt aus dem Zugriff der KI auf das Postfach. Deshalb 11.1.
- **Keine Zusage über die Zustellung.** 202 heißt, Graph hat die Antwort angenommen.

## 12. Senden an freie Empfänger (Opt-in): das Werkzeug `send_mail`

Seit Fassung **4.0.0** (PO-Entscheid 21.11.2026: voller Zugriff, auch an andere senden, ohne Tageslimit) gibt es neben `reply` ein
zweites Sendewerkzeug: `send_mail` sendet **eine neue Mail** an eine frei wählbare
Adresse, optional mit einer Kopie (`cc`), ohne Tagesdeckel. Es gibt **keinen
Freigabeklick**, und die Empfänger sind nicht auf eine Liste beschränkt. Der Text ist
Klartext; es gibt kein HTML, keine Anhänge, kein BCC und keine Antwortadresse. `to` ist
genau **eine** Adresse und `cc` höchstens **eine** (das Spec-Format erzeugt aus einem
Parameter keine Listeneinträge). Für die Antwort auf eine vorhandene Mail bleibt `reply`
der Weg, für eine Mail, die ein Mensch prüfen soll, `create_draft`.

Der Body ist genau festgelegt: `message` mit Betreff, Text, `toRecipients` und optional
`ccRecipients`, dazu `saveToSentItems: true`. Ohne `saveToSentItems` gäbe es nirgends
einen Beleg, weil das Audit den Text schwärzt. Fehlt `cc`, entfällt `ccRecipients` ganz.

### 12.1 Die Grenze: Exchange-Rolle mit eigenem Scope, tool-genaues Recht

- **Exchange:** `Mail.Send` gibt es auch hier **nur als Exchange-Rolle**
  `Application Mail.Send` über RBAC for Applications, mit einem **eigenen Management Scope**
  allein auf das Sende-Postfach (Befehle wie in 11.2) — **keine Graph-API-Berechtigung**
  `Mail.Send`. Das ist die eigentliche Grenze: `mailbox` ist ein Parameter, den die KI
  wählt, und ein anderes als das freigegebene Postfach lehnt Exchange mit 403 ab.
- **Opt-in:** `send_mail` wird bei der Neuanlage **nicht vorgewählt**; der Admin hakt es
  ausdrücklich an (REST und Admin-MCP verlangen ohnehin eine Werkzeugliste). Bei einer
  Anhebung kommt es nur mit `jnpt connector upgrade <name> --werkzeug send_mail --yes`
  bzw. `add_tools` auf die Integration. Ein `jnpt connector add --file` übernimmt **alle
  Werkzeuge der Datei**, also auch `send_mail`; wer es nicht will, entfernt den Block
  `- name: send_mail` vorher.
- **Das Recht ist tool-genau:** `jnpt token allow <token-id> microsoft-graph-mail:send_mail`
  (bei einer Integration mit anderem Namen deren Name). Ein Scope auf die ganze
  Integration erfasst `send_mail` nicht, und das Recht auf `reply` oder `create_draft`
  öffnet es nicht.
- **Geteiltes Credential:** Eine Installation kann das Credential mit der Fehlerwache
  teilen (gleiche App, gleicher Scope auf genau ein Postfach), siehe
  (Produkt-Doku, nicht öffentlich); wer den
  Management Scope der App ändert, ändert damit beide Installationen.
- **Das Token** einer solchen Installation trägt nur `<integration>:send_mail`; der
  Klartext liegt allein in einer Datei auf dem Rechner des Betreibers (Zugriff nur für den
  Benutzer) und nie in einem Repo, und im Probelauf-Vermerk steht nur die Token-ID.

### 12.2 Was im Audit steht — und was nicht

Postfach, Empfänger und Betreff (`mailbox`, `to`, `cc`, `subject`) stehen im Klartext
im Audit, damit jede Mail zurechenbar bleibt; ein geschwärztes `cc` versteckte einen
Empfänger. Geschwärzt ist allein der Text (`content`). Den Wortlaut belegen „Gesendete
Elemente“ des Postfachs. Die Redaktionsliste der Vorlage ist genau `content` und `comment`.

### 12.3 Probelauf: ein echter Versand und eine Gegenprobe

`send_mail` hat **kein `dry_run`** (bewusste Ausnahme; sie steht im Kopf der Vorlage).
Der Probelauf nach jeder neuen Fassung, nach der Wirkzeit der Richtlinie (Schritt 4):

1. **Ein echter Versand** an ein **eigenes Postfach** des Betreibers. Erwartet: das Ergebnis
   `{"status": 202}`, ein Audit-Eintrag mit Status `ok` und Empfänger und Betreff im
   Klartext, aber ohne Text, und die Mail in **„Gesendete Elemente“** des Sende-Postfachs.
2. **Gegenprobe:** `send_mail` mit einem **zweiten, nicht freigegebenen Postfach** als
   `mailbox`. Erwartet: **403**. Bei 202 nicht weitermachen und die Rolle, den Scope und
   die Entra-Zustimmung prüfen. Die Uhrzeit der Probe und die Klasse
   der Antwort gehören in den Vermerk.

### 12.4 Ehrliche Grenzen

- **Freie Empfänger heißt frei.** Der Kern prüft keine Adresse und keine Domain. Ein
  falsch angeleitetes Modell kann an jede Adresse senden, auch mit Inhalten, die es über
  andere Tokens derselben Sitzung gelesen hat (angenommen mit dem PO-Entscheid vom
  21.11.2026). Begrenzt wird das durch den Exchange-Scope auf **ein** Postfach, durch das
  tool-genaue Recht und durch den Beleg in „Gesendete Elemente“.
- **Ein Fehler wird nicht blind wiederholt:** Er kann die Mail doppelt senden. Erst in
  „Gesendete Elemente“ nachsehen.
- **Empfehlung (keine Regel, der Betreiber entscheidet):** das eigene Postfach als `cc`
  in jede Mail setzen oder in Exchange eine Transportregel mit Kopie an ein menschliches
  Postfach anlegen. Dann sieht ein Mensch jede gesendete Mail sofort.
- **Keine Zusage über die Zustellung.** 202 heißt, Graph hat die Mail angenommen.

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
