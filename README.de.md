# januaport-integrations

[English](README.md) · **Deutsch**

Ausgang für JanuaPort: Connector-Specs, Spec-Formate, Katalog und Beispiel-Konfigurationen, also alles, was JanuaPort an fremden Systemen anspricht.

JanuaPort ist ein self-hosted MCP-Gateway. Es verbindet KI-Assistenten fein berechtigt mit den
bestehenden Systemen eines Unternehmens und protokolliert die Zugriffe in einem append-only Audit-Log. Der
Kern von JanuaPort ist proprietäre Software der JanuaPort GmbH und nicht Teil dieses Repositorys. Dieses
Repository ist einer der offenen Ränder darum herum.

- **Lizenz:** Apache License 2.0 ([`LICENSE`](LICENSE), [`NOTICE`](NOTICE))
- **Links:** [januaport.ai](https://januaport.ai) · [Sicherheitsrichtlinie](SECURITY.md) · [Beiträge](CONTRIBUTING.md)

Keine Kundendaten, keine Schlüssel, keine Betreiberwerte in diesem Repository.

---

## Worum es geht

JanuaPort macht aus einem Bestandssystem — ERP, Buchhaltung, Postfach, Dateiablage —
fein berechtigte MCP-Werkzeuge für KI-Agenten. **Was JanuaPort dabei anspricht, steht
hier:** eine Spec beschreibt in YAML, welche Aufrufe an ein fremdes System erlaubt sind
und wie deren Antwort beim Agenten ankommt. Aus jeder Spec entstehen beim Laden
MCP-Werkzeuge; Berechtigung, Pseudonymisierung und Audit legt das Gateway darüber. Die
Pseudonymisierung ist deterministisch und regelbasiert, ohne Sprachmodell im Pfad, und greift nur, wo sie
eingerichtet ist: Sie ersetzt durch feste Kürzel nur die Felder, die der Betreiber deklariert, und im
Fließtext nur, wofür der Betreiber ein Muster zuweist (z. B. IBAN, E-Mail, Telefon). Namen im Fließtext
erkennt sie nicht.

Eine Spec ist **Konfiguration, kein Code** — sie wird gelesen, nicht ausgeführt. Deshalb
kann sie von außen beigetragen und geprüft werden, ohne dass jemand das Gateway anfasst.

## Was hier liegt

| Ordner | Inhalt |
|---|---|
| [`connector-specs/`](connector-specs/) | Die ausgelieferten REST-Specs — 17 Stück, Tabelle unten. |
| [`upstream-specs/`](upstream-specs/) | Beispiel-Konfiguration für einen **MCP-Upstream** (fremder MCP-Server unter unserer Governance): `github.yaml`. |
| [`docs/`](docs/) | Die vier Format-Verträge, die Bau-Disziplin und drei Betreiber-Anleitungen. |
| [`examples/`](examples/) | Beilagen zu den Anleitungen (heute: das Exchange-Skript zur Ein-Postfach-Grenze). |

## Die vier Format-Verträge

Vier Integrationsarten, vier Formate. Welche die richtige ist, entscheidet sich **vor**
dem Bau — die Faustregel steht in [`docs/connector-treue.md`](docs/connector-treue.md) §8:
*Gibt es für das System bereits einen MCP-Server, ist er der Weg.*

| Art | Vertrag | Wofür |
|---|---|---|
| REST-Connector | [`docs/connector-spec.md`](docs/connector-spec.md) | System mit brauchbarer REST-API — ein Tool je Endpunkt. |
| MCP-Upstream | [`docs/upstream-mcp.md`](docs/upstream-mcp.md) | Für das System existiert ein MCP-Server: proxen statt nachbauen. |
| Datenbank | [`docs/db-connector-spec.md`](docs/db-connector-spec.md) | Bestandssystem ohne API, aber mit Datenbank — kuratierte Sicht statt freier SQL-Zugriff. |
| Datei | [`docs/file-connector-spec.md`](docs/file-connector-spec.md) | Was als Datei in ein Verzeichnis fällt (z. B. ein Kontoauszug). |

Dazu: [`docs/connector-treue.md`](docs/connector-treue.md) — Auth-Muster, die verbindliche
Bau-Disziplin und wann ein Upstream die bessere Wahl ist.

## Wie eine Spec entsteht

1. **Integrationsart wählen** (Tabelle oben). Ein REST-Connector, der einen vorhandenen
   MCP-Server in YAML nachbaut, ist doppelte Arbeit mit halber Abdeckung.
2. **Doku zuerst.** Aus der offiziellen Anbieter-Dokumentation arbeiten — Endpunkt,
   Parameter, Antwort **und die Kopfzeilen der Anfrage**. Die Doku-Stelle wird notiert,
   nicht nur gelesen; sie gehört zum Beitrag.
3. **Spec schreiben.** `version` ist Pflicht (SemVer). Die Werkzeug-Beschreibungen sind
   ein **Produktmerkmal**, kein Beiwerk: Eine KI wählt allein danach aus, was sie
   aufruft. Schreibende Werkzeuge werden einzeln als solche gekennzeichnet.
4. **Live prüfen.** `jnpt connector check` läuft in vier Stufen bis zum echten Aufruf
   gegen die echte API.
5. **Belegen.** Was beobachtet wurde, gehört in den Beitrag — ohne Zugangsdaten und ohne
   echte Daten.

### Doku zuerst, dann live — und warum beides

**Doku zuerst** verhindert erfundene Aufrufe. **Live danach** verhindert den teureren
Fehler: eine Spec, die *aussieht* wie die Dokumentation und trotzdem nicht funktioniert.
Beides ist bei uns Lehrgeld, kein Prinzip — Endpunkte, die ohne den richtigen
`Accept`-Header mit 400 antworten, Berechtigungen, die erst ressourcenseitig greifen,
Fehlermeldungen, die „es gibt nichts“ als „der Aufruf ist kaputt“ ausgeben. Keiner dieser
Fälle stand in einer Dokumentation.

**Der Live-Beleg ist Definition of Done — auch für Beiträge von außen.** Kein Werkzeug
gilt als fertig ohne einen echten Erfolg gegen das echte System (200 beim Lesen,
kontrollierter Erfolg beim Schreiben), beschrieben im Pull Request. Wer keinen echten
Zugang zu dem System hat, sagt das: **Ein ungeprüfter Entwurf ist willkommen** — er wird
dann als Entwurf geführt und nicht als geprüft zusammengeführt. Das ist keine Hürde
gegen Beiträge, sondern die Zusage, dass hier nichts liegt, was nur auf dem Papier geht.

## Was ins Produkt gelangt

**Nur gegatete Specs.** Dieses Repository ist die Werkbank, nicht der Auslieferungskanal:
Ein Merge hier ist noch keine Zusage, dass eine Spec im Produkt erscheint. Der Katalog im
JanuaPort-Image ist eine **kuratierte Auswahl** — jede aufgenommene Spec durchläuft das
Quality Gate der JanuaPort GmbH (Format, Sicherheits-Invarianten, Live-Beleg, Pflegezusage).
Was hier liegt und nicht ausgeliefert wird, bleibt trotzdem nutzbar: Ein Betreiber kann
jede Spec selbst in sein Connector-Verzeichnis legen.

## Stand der ausgelieferten Specs

Kennzeichnung: **Gebaut** · **Im Bau** · **Geplant**. „Live belegt“ heißt: gegen das echte System
gelaufen, im Backlog dokumentiert.

| Spec | Werkzeuge | Stand |
|---|---|---|
| [`google-search-console.yaml`](connector-specs/google-search-console.yaml) (1.0.0) | 4, lesend | Gebaut, synthetisch geprüft; Live-Abnahme offen. Privater Beisteller, feste öffentliche Seitenliste. Query-Freitext bis SEC gesperrt; Auditmetadaten nötig. |
| [`google-analytics.yaml`](connector-specs/google-analytics.yaml) (1.0.0) | 4, lesend | Gebaut, synthetisch geprüft; Live-Abnahme offen. Feste GA4-Aggregate, Host-/Seitenfilter, optionaler Key-Event-Messvertrag. |
| [`demo-erp.yaml`](connector-specs/demo-erp.yaml) | 2, lesend | **Gebaut, nur zur Vorführung.** Attrappe für den Rundgang — spricht ein erfundenes ERP an, kein echtes System. Braucht das Beispiel-ERP aus dem Produkt-Repository. |
| [`dokumente.yaml`](connector-specs/dokumente.yaml) | 4, lesend | **Gebaut.** Live belegt (20.09.2026): alle vier Prüfstufen grün, Suche über `/mcp` mit erwartetem Treffer, Audit mit redigiertem Suchbegriff. Vorlage — ein Wissensbereich je Integration. |
| [`lexware-office.yaml`](connector-specs/lexware-office.yaml) | 6, davon 2 schreibend | **Gebaut.** Lesen live belegt. Die beiden schreibenden Werkzeuge (Beleg hochladen, Belegbild anheften) sind gebaut, **der Live-Beleg des Schreibwegs steht aus**. |
| [`microsoft-graph-mail.yaml`](connector-specs/microsoft-graph-mail.yaml) | 8 insgesamt: 5 YAML + 3 nativ, davon 4 schreibend | **Gebaut.** Live belegt (06./07.08.2026): Lesen mit 200, Entwurf real angelegt samt Gegenprobe „nichts versendet“. **Ein-Postfach-Grenze belegt (13.08.2026):** zweites, existierendes Postfach antwortet mit 403. Kein Sende-Werkzeug — bewusst. Native Werkzeuge: `save_attachment`, `move_message`, `mark_read`; YAML bleibt auf 2.0.2. |
| [`microsoft-graph-sharepoint.yaml`](connector-specs/microsoft-graph-sharepoint.yaml) | 4, lesend | **Gebaut.** Live belegt am echten Tenant (25.08.2026): 403 vor dem Site-Grant, 200 danach. Nur Metadaten, nie Datei-Inhalte. Vorlage 2.0.0 nutzt eine Site-ID als Instanzwert; diese neue Form ist noch nicht live belegt. |
| [`business-central.yaml`](connector-specs/business-central.yaml) (2.0.0) | 11, lesend | Gebaut; Live-Beleg ausstehend. Online-API v2.0, eine Firma in einer Umgebung; Mandant und Firma sind Instanzwerte. |
| [`hubspot.yaml`](connector-specs/hubspot.yaml) (1.0.0) | 8, lesend | Gebaut; Live-Beleg ausstehend. Kontakte, Firmen und Deals; lesende Suchen per POST. |
| [`jtl-wawi.yaml`](connector-specs/jtl-wawi.yaml) (1.0.0) | 10, lesend | Gebaut; Live-Beleg ausstehend. On-Prem-API-Version 2.0; feste Request-Header, kein Schreiben. |
| [`microsoft-graph-calendar.yaml`](connector-specs/microsoft-graph-calendar.yaml) (1.0.0) | 3, lesend | Gebaut; Live-Beleg ausstehend. Ein Postfach; keine Teilnehmer und kein Termintext. |
| [`odoo.yaml`](connector-specs/odoo.yaml) (3.1.0) | 15, davon 4 schreibend | Gebaut. Werkzeuge der früheren 3.0.0 live belegt (30.09.2026); Datenbank-Instanzwert der 3.1.0 noch nicht live belegt. Chatter benötigt eine eigene Integration mit internem Odoo-Nutzer. Das Vertragsmodell ist eine Erweiterung, kein Odoo-Standard. |
| [`openproject.yaml`](connector-specs/openproject.yaml) (1.0.0) | 7, lesend | Gebaut; live belegt gegen 17.8.0 (30.09.2026). Projekte und Arbeitspakete; keine Zeitbuchungen und keine Nutzerlisten. |
| [`paperless.yaml`](connector-specs/paperless.yaml) (1.0.0) | 6, lesend | Gebaut; live belegt gegen 3.2.1 (30.09.2026). Nur Metadaten; kein OCR-Text, Datei-Inhalt oder Download. |
| [`shopware-admin.yaml`](connector-specs/shopware-admin.yaml) (1.0.0) | 6, lesend | Gebaut; live belegt gegen 6.7.14.2 (29.09.2026). ACL-Rolle nur lesend; JSON-Antwortformat und geerbte Variantennamen. |
| [`woocommerce.yaml`](connector-specs/woocommerce.yaml) (1.0.0) | 7, lesend | Gebaut; live belegt gegen 11.1.2 (30.09.2026). Read-Key per Basic über HTTPS; feste Feldlisten. |
| [`zammad.yaml`](connector-specs/zammad.yaml) (1.0.0) | 7, lesend | Gebaut; live belegt gegen 7.2.0 (30.09.2026). Nur Metadaten; keine Artikel oder Notizen. Der Anbieter-Token kann Kunden und Organisationen schreiben; JanuaPort bietet nur GET-Werkzeuge an. |
| [`upstream-specs/github.yaml`](upstream-specs/github.yaml) | Allowlist | **Gebaut.** Ausgeliefert seit v0.2.0, Lese-Relay live belegt. Beispiel für das Instanz-Modell: dieselbe URL, verschiedene Zugänge und Allowlists. |

Die Vorlagen tragen die Produktversionen. Weitere Anbieter-Anleitungen bleiben
Produkt-Doku, nicht öffentlich; Formatregeln und Herstellerverweise stehen in den
Spec-Kommentaren und in der [Bau-Disziplin](docs/connector-treue.md). Die Live-Belege
oben stammen aus dem Produkt; dieser Spiegel-Nachzug wurde lokal ohne
Anbieter-Aufrufe geprüft.

Betreiber-Anleitungen liegen für die beiden Graph-Connectoren bei
([Postfach](docs/connector-microsoft-graph-mail.md),
[SharePoint](docs/connector-microsoft-graph-sharepoint.md)) — sie beschreiben die
Einrichtung auf der **Gegenseite** (App-Registrierung, Berechtigungen, Grenzen) und sind
zugleich das Muster dafür, wie eine Spec dokumentiert sein sollte.

## Hinweise zum Lesen

- **`#`-Nummern** (z. B. `#347`) verweisen auf das Backlog des Produkt-Repositoriums, das
  heute geschlossen ist. Sie nennen die Herkunft einer Entscheidung und sind kein Link.
- **„(Produkt-Doku, nicht öffentlich)“** markiert einen Verweis auf eine Datei, die im
  geschlossenen Kern liegt. Der umgebende Absatz steht für sich; es fehlt nur die
  Vertiefung.
- **Für Datenbank- und Datei-Specs gibt es hier noch keine eigenständige
  Beispieldatei** — das vollständige Beispiel steht jeweils im Format-Vertrag selbst
  (Abschnitt „Vollständiges Beispiel“). Datei-Specs erzeugt das Produkt in aller Regel
  selbst, sie werden nicht von Hand geschrieben.

## Google Reporting (#1130)

[Search Console und GA4](docs/connector-google-reporting.md): zwei Vorlagen 1.0.0, acht feste Lesewerkzeuge über den privaten Google-Reporting-Beisteller. Stufe 1, gebaut/synthetisch geprüft; Live-Abnahme offen. Queryfreitext bleibt bis SEC gesperrt; Auditmetadaten sind Betriebsbedingung.
