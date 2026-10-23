# Google Search Console und GA4 über Google Reporting (#1130)

Stufe 1 „Sicher verbinden“: zwei REST-Vorlagen 1.0.0, acht lesende Werkzeuge.
Gebaut und synthetisch geprüft; Live-Abnahme/Release offen. Keine Google-Anmeldung
im Gateway: der private Beisteller `google-reporting` aus januaport-plugins nutzt
offizielle Google-Clients, feste Properties, getrennte readonly Scopes,
freigegebene Hosts/Pfade und feste Berichte.

`google-search-console.yaml`: get_status, performance_overview, query_summary,
page_summary. `google-analytics.yaml`: get_status, traffic_summary, landing_pages,
key_events. Endgültige MCP-Namen verwenden den Instanznamen als Präfix.
Beide Vorlagen nennen dieselbe Connector-Credential `google-reporting`: **ein**
Bridge-Key für beide Quellen, gleich dem `runtime-key` der Stelle
`plugin-google-reporting`. Der Bridge-Key ist ein Zufallswert, den kein Mensch kennen
muss: Der Betreiber erzeugt ihn auf der Anlage und setzt ihn per Betreiber-CLI über
stdin in die Stelle und mit demselben Wert in die Credential; danach wird er
verworfen (nie in Chat, Log oder Datei). Nur das Servicekonto-JSON (Stelle
`plugin-google-reporting-google`) trägt der Admin in der Admin-GUI unter
Basis-Einrichtung ein. Beides steht nur im Tresor (auf der Anlage als RAM-Datei); die
Rechte je Werkzeug prüft das Gateway. Interne base_url
http://google-reporting:8092.

## Betreiberfolge

1. Vollständiges Runbook im Plugin `google-reporting/README.md` abarbeiten:
   zweckgebundenes Servicekonto/Property-Lesegrants, Servicekonto-JSON nur über die
   Admin-GUI (Basis-Einrichtung) eintragen und die heruntergeladene Datei löschen,
   Zeitzone,1–50 exakte öffentliche Pfade in disjunkten atas/gateway/shared-Gruppen,
   explizite kanonische URLs. Keine personenbezogenen Pfade. GA filtert immer
   landingPage UND hostName; feste Kombinationen live prüfen.
2. Internes jnpt_plugins-Netz erhalten; Dienst nur an dessen reservierte IP binden,
   zusätzlich dediziertes Egress-Netz und geprüfte Host-Zielregeln. Kein Host-Port/
   öffentliches Routing. Dockerhealth prüft lokal; get_status prüft Googlezugriff.
3. **Wirksame Audit-Tiefe metadaten für SSO UND Token** prüfen. Alle deklarierten
   Parameter stehen in redact_params. Bei abfragen/antworten können deklarierte
   Werte trotzdem im Audit-Inhalt stehen. Einstellung ist je Zugangsklasse,
   nicht je Integration. Bei verbindlich höherer Tiefe eigener LEAD/SEC-Schnitt;
   diese Vorlagen verändern keine globale Einstellung.
4. Die Vault-Credential `google-reporting` (Wert gleich `runtime-key` der Stelle
   `plugin-google-reporting`) setzt der Betreiber per `jnpt credential set` über stdin
   zusammen mit der Stelle (Runbook im Plugin `google-reporting/README.md`),
   daraus bewusst **corp**-Instanzen erstellen. Team-Selbstanlage erlaubt nur
   öffentliche HTTPS-Ziele. Admin-MCP benötigt target_address-Schalter für private
   Ziele; alternativ Betreiberweg. Nur vorgesehenem INBOUND-Zugang Rechte geben.
   Pluginaktivierung erstellt keine Instanzen/Rechte. Token ohne Scope sieht/ruft
   keine Berichte. Klartextfreigabe bleibt explizite Betreiberentscheidung.
5. Status/Negativproben durchführen, „JanuaPort SSO Neu“ Werkzeuge neu laden,
   dann freigegebene Berichte. Erstmalige Katalogauslieferung kann Neustart
   benötigen; vorhandener REST-Lifecycle/Reload bleibt. Produkt-/Integrations-
   Vorlage mit gleicher Versionsnummer müssen **bytegleich** sein.

## Eingabe-, Daten- und Privacyvertrag

period_days 28 oder 90, Default 28; optionales ISO-end_date inklusiv höchstens
Quelle-heute minus drei Tage. GSC America/Los_Angeles, GA4 Property-Zeitzone.
segment all_public/atas/gateway/shared, optional exakter GSC-page_path innerhalb
Segment. Ranglisten-limit 1–100, Default 25, Übersicht höchstens 90 Tage.
Keine freien Properties/Dimensionen/Metriken/Filter/Offsets oder Autoexport.
Zahlengrenzen/Datum/Kombinationen prüft der Beisteller vor Token/Google. Gateway
prüft Enums/einfache Typen; numerische Enums sind im Vorlagenformat nicht verfügbar.
Zusätzliche MCP-Argumente ignoriert die bestehende Runtime, schwärzt ihre Werte
und leitet sie nicht weiter. Unbekannte/doppelte HTTP-Parameter lehnt der Dienst ab.

Antworten unterscheiden ok/partial/no_rows/not_configured, echte Null und
unterdrückte/fehlende Messung. Qualität nennt Grenzen, Sampling/Thresholding,
(other), Metrikbeschränkung, Zeilen-/Limitinformationen und sichere Quotenwerte.
Fehlende Quellenmerkmale bleiben unbekannt. GSC ist begrenzte Top-Zeilen-Sicht:
Auswahl nicht als Gesamtwert summieren; CTR/Position nicht arithmetisch mitteln.
GA-Sessions sind keine GSC-Klicks. KeyEvents sind bestehende freigegebene Ereignisse,
keine qualifizierten Leads/Odoo-Ergebnisse. Fehlender oder für den Zeitraum
ungültiger Messvertrag liefert not_configured; Traffic bleibt nutzbar.

**Query-Sicht ist standardmäßig deaktiviert** (Betreiberschalter `query_enabled`;
erster Start mit `false`, danach ohne weitere SEC-Prüfung einschaltbar, sobald die
Zahlenberichte live belegt sind). Dienst unterdrückt Gruppen unter query_min_impressions (mindestens 10).
Vorlage scannt rekursiv das JSON-Feld query mit email/telefon/iban. Keine
Anonymisierung und keine Erkennung aller Namen. Numerische Berichte können separat
freigegeben werden. GA-Landingpage-/Key-Event-Mindestgröße wird im Messvertrag
konfiguriert (Default 10); unterdrückte Gruppen sind keine Nullen, Schwelle schützt
nicht vor Differenzangriffen. Kein Nutzerbezug, Tracking-Anlage oder Odooexport.

Dienstgrenzen:512 KiB Antwort,8 KiB URL/Query, Pfad 512 Zeichen,20 s Gesamtbudget inkl.
Queue/Auth/API, zwei killbare persistente Worker,30 Berichts-/Probeanforderungen
pro Quelle/Minute, keine SDK-/Token-Retry-Kette. Connector 25 s und min_interval500 ms.
Dienstlog nur Route/Code/Dauer. JanuaPort zeigt Nicht-2xx als bestehende Statusmeldung
und unterdrückt den Body; normale Fehler werden nie leere HTTP200-Erfolgsberichte.
get_status bietet feste Diagnosezustände ohne Property-ID/Google-Rohfehler.

Stop/Deaktivierung: Fehler statt Nullbericht. Rotation: Bridge-Key neu
erzeugen und in Stelle und Credential setzen, Servicekonto-JSON in der Admin-GUI
eintragen (das Unit-Paar des Plugins erzeugt den Container neu), positive Probe,
alten Google-Schlüssel in der Cloud Console löschen. Die Schlüssel reisen mit dem
Tresor im Backup. **Entfernen ist kein Widerruf:** Der Google-Schlüssel bleibt gültig,
bis er in der Cloud Console gelöscht ist. Vollständiger Rückbau entfernt
Connectorrechte/-instanzen und widerruft Google-Grants/Bridge-Key;
Plugin-Purge erledigt das nicht automatisch. Signierter Service-Katalog/Image-
Digest wird erst im getrennten GATE/VENDOR-Release bereitgestellt.

Offene P3-Gates: Zielhost-Egress/Listenernachweis, minimale Grants und negative
Liveprobe, GA-Kompatibilität, Consent/Seiten-/Messvertrag, SEC/Auditfreigabe,
Vergleich mit Quellenoberflächen und je Quelle echter 28/90-Tage-Abruf über
ChatGPT → JanuaPort SSO Neu → Connector → Beisteller → Google.

API: [GSC](https://developers.google.com/webmaster-tools/v1/searchanalytics/query),
[GA4](https://developers.google.com/analytics/devguides/reporting/data/v1/rest/v1beta/properties/runReport).

## Schreibhandgriffe (zwei weitere Vorlagen 1.0.0)

`google-search-console-manage.yaml`: list_sitemaps, get_sitemap, inspect_url und
submit_sitemap (schreibend). `google-analytics-manage.yaml`: list_annotations,
create_annotation und update_annotation (schreibend), list_channel_groups,
create_channel_group und update_channel_group (schreibend). Die Lesevorlagen bleiben
unverändert; die Freigabe einer ganzen Lese-Integration gibt kein Schreibrecht.

- Jedes Schreibwerkzeug trägt ein tool-genaues Recht und kennt `dry_run`; die Antwort
  zeigt `before` und `after`. Löschen und Archivieren gibt es nicht.
- Der Beisteller holt für Schreibaufrufe eigene Scopes (`webmasters`, `analytics.edit`),
  getrennt von den Lesescopes. Site und Property kommen aus der Betreiberkonfiguration.
- Je Quelle gelten höchstens 20 Schreibversuche am Tag im Serverprozess; jede
  angewandte Änderung ergibt eine Änderungszeile im Beisteller-Log.
- Grenzen der Google-APIs: Einreichen einer Sitemap löst kein Crawling aus,
  „Indexierung beantragen“ hat keine öffentliche API. Annotationen und Kanalgruppen
  gibt es nur in der Admin API v1alpha, deren Form sich ändern kann.
- Rechte des Servicekontos: Search Console „Uneingeschränkt“, GA4 „Bearbeiter“.

Live belegt am 22.10.2026: eine Annotation, eine eingereichte Sitemap und eine
Kanalgruppe, jeweils erst als Vorschau, dann einmal echt.

API: [Sitemaps](https://developers.google.com/webmaster-tools/v1/sitemaps/submit),
[URL-Inspektion](https://developers.google.com/webmaster-tools/v1/urlInspection.index/inspect),
[Annotationen](https://developers.google.com/analytics/devguides/config/admin/v1/rest/v1alpha/properties.reportingDataAnnotations),
[Kanalgruppen](https://developers.google.com/analytics/devguides/config/admin/v1/rest/v1alpha/properties.channelGroups).
