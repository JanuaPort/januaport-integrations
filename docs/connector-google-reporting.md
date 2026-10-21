# Google Search Console und GA4 über Google Reporting (#1130)

Stufe 1 „Sicher verbinden“: zwei REST-Vorlagen 1.0.0, acht lesende Werkzeuge.
Gebaut und synthetisch geprüft; Live-Abnahme/Release offen. Keine Google-Anmeldung
im Gateway: der private Beisteller `google-reporting` aus januaport-plugins nutzt
offizielle Google-Clients, feste Properties, getrennte readonly Scopes,
freigegebene Hosts/Pfade und feste Berichte.

`google-search-console.yaml`: get_status, performance_overview, query_summary,
page_summary. `google-analytics.yaml`: get_status, traffic_summary, landing_pages,
key_events. Endgültige MCP-Namen verwenden den Instanznamen als Präfix.
Bridge-Keys sind voneinander unabhängig, nur im Vault/geschützten Hostdateien;
GSC-Key öffnet keine GA4-Route. Interne base_url http://google-reporting:8092.

## Betreiberfolge

1. Vollständiges Runbook im Plugin `google-reporting/README.md` abarbeiten:
   zweckgebundenes Servicekonto/Property-Lesegrants, syntaktisch geprüfte Secretdatei,
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
4. Zwei Vault-Credentials google-search-console und google-analytics anlegen,
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

**Query-Sicht ist standardmäßig deaktiviert**, bis SEC den verbleibenden Freitext
akzeptiert. Dienst unterdrückt Gruppen unter query_min_impressions (mindestens 10).
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

Stop/Deaktivierung: Fehler statt Nullbericht. Rotation erfordert neue geschützte
Dateien, Container-Recreate, Vault-Abgleich, positive Probe und Widerruf der alten
Keys. Host-Secrets gehören nicht automatisch zum Vaultbackup. Vollständiger Rückbau
entfernt Connectorrechte/-instanzen und widerruft Google-Grants/Bridge-Keys;
Plugin-Purge erledigt das nicht automatisch. Signierter Service-Katalog/Image-
Digest wird erst im getrennten GATE/VENDOR-Release bereitgestellt.

Offene P3-Gates: Zielhost-Egress/Listenernachweis, minimale Grants und negative
Liveprobe, GA-Kompatibilität, Consent/Seiten-/Messvertrag, SEC/Auditfreigabe,
Vergleich mit Quellenoberflächen und je Quelle echter 28/90-Tage-Abruf über
ChatGPT → JanuaPort SSO Neu → Connector → Beisteller → Google.

API: [GSC](https://developers.google.com/webmaster-tools/v1/searchanalytics/query),
[GA4](https://developers.google.com/analytics/devguides/reporting/data/v1/rest/v1beta/properties/runReport).
