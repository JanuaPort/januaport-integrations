# Datenbank-Spec — Format-Referenz

Eine Datenbank-Integration ist eine YAML-Datei, die aus **hinterlegten,
parametrisierten SELECT-Abfragen** berechtigte MCP-Tools macht. JanuaPort lädt beim
Start alle `*.yaml`/`*.yml` aus dem Datenbank-Verzeichnis
(`JNPT_DATABASES_DIR`, Default `/data/databases`), prüft sie und bietet ihre
Tools über den MCP-Endpoint an. Diese Seite ist die Referenz zum
Selber-Schreiben — keine Programmierkenntnisse nötig, aber SQL-Kenntnisse.

Sie ist die **dritte Integrationsart** neben dem [REST-Connector](connector-spec.md)
und dem [Upstream-MCP-Server](upstream-mcp.md). Gedacht für die häufigste Lücke
im deutschen Mittelstand: **ein Bestandssystem ohne brauchbare API, aber mit
einer Datenbank, in die man lesen darf.**

> ### Die zwei Sätze, auf die alles aufbaut
>
> **Der Agent sieht Name, Beschreibung und die deklarierten Parameter — NIE das
> SQL.** Er kann keine Abfrage formulieren, keine Tabelle erkunden und keine
> Spalte erraten. Es gibt kein `run_sql(query)` und wird keines geben.
>
> **Ein Tool ist genau EIN Statement.** Lesend ein `SELECT` (bzw.
> `WITH … SELECT`), schreibend ein `INSERT` oder ein `UPDATE` — mehr nicht. Kein
> `DELETE`, kein DDL, keine Prozeduren: Ein Agent darf einen Geschäftsvorfall
> ergänzen oder fortschreiben, nicht Bestand vernichten und nicht die Struktur
> ändern.

## Vollständiges Beispiel

```yaml
name: demo-wawi                     # eindeutiger Name (Prefix der Tool-Namen)
driver: postgres                    # v1: nur postgres

connection:
  host: 192.168.1.10                # Pflicht
  port: 5432                        # optional, Default 5432
  database: wawi                    # Pflicht
  user: jnpt_readonly               # Pflicht — kein Secret, sondern reviewbar
  sslmode: require                  # PFLICHT: disable | require | verify-ca | verify-full

credential: demo-wawi-db            # NAME des Passworts im Vault — nie das Passwort
timeout: 10s                        # optional: je Aufruf; Default 10s, Obergrenze 60s
redact_params: [kunde]              # optional: diese Parameter erscheinen im Audit als [REDACTED]

tools:
  - name: list_open_orders
    description: >
      Lists orders of one customer, newest first. Returns order number, date,
      gross amount, status and the customer name. Filter by status with the
      optional "status" parameter (offen, bezahlt, storniert); omit it to get
      every status. Dates are ISO 8601 (YYYY-MM-DD).
    params:
      - name: kunde
        description: The customer number, e.g. K-1001.
        type: string
        required: true
      - name: status
        description: Optional status filter — one of offen, bezahlt, storniert.
        type: string
        enum: [offen, bezahlt, storniert]
    query: |
      SELECT a.auftrag_nr, a.datum, a.betrag, a.status, k.kunde_name
      FROM wawi.auftraege a
      JOIN wawi.kunden k ON k.kunde_nr = a.kunde_nr
      WHERE a.kunde_nr = @kunde
        AND (@status::text IS NULL OR a.status = @status)
      ORDER BY a.datum DESC
    max_rows: 200                   # optional, Default 500, harte Obergrenze 5000
    privacy:                        # optional; field = SPALTENNAME
      read:
        - { field: kunde_name, label: name }
```

Die vollständige, lauffähige Demo-Spec samt Beispiel-Schema liegt im Repository:
`internal/sqlconnector/runtime/testdata/demo-wawi.yaml` und `…/seed_wawi.sql`.

## Felder im Detail

### Oberste Ebene

| Feld | Pflicht | Bedeutung |
|---|---|---|
| `name` | ja | Eindeutiger Name der Integration. Wird zum **Prefix** jedes Tool-Namens (`demo_wawi_list_open_orders`); Bindestriche werden zu Unterstrichen. Zugleich die **Berechtigungs-Identität** (`name` bzw. `name:tool` als Scope) — er muss über **alle** Integrationsarten eindeutig sein, sonst startet der Gateway nicht. ⚠️ **Seit Bug #596:** Ein Name, der nach dieser Normalisierung kein gültiges Präfix ergibt (Großbuchstaben, Umlaute, Punkt, Leerzeichen, führende Ziffer), wird bei der **Anlage über die Admin-Fläche abgelehnt**; ein solcher Name im **Bestand** hält den Start NICHT auf, erzeugt aber beim Start eine **WARN-Zeile** mit Namen und Grund. Umbenannt wird nichts automatisch — ein Rename berührt Scopes, Tokens und Team-Zuordnungen. **Reserviert** (das Gateway belegt diese Namen selbst — eine Integration dieses Namens verhindert den Start): `memory`, `kartei`, `usecase` (#642), `wissen` (#647), `ablage` (#726), `ping`, `catalog`, `report_problem`. |
| `driver` | ja | v1: nur `postgres`. Jeder andere Wert ist ein Ladefehler; die Meldung zählt die unterstützten Treiber auf. |
| `connection` | ja | Die reviewbaren Verbindungsangaben (siehe unten) — **ohne Passwort**. |
| `credential` | ja | **Name** des Datenbank-Passworts im Vault, nie das Passwort selbst. Anlegen mit `jnpt credential set --name <name>`. Gehört zum **Lese-Benutzer**. |
| `write_user` | nein | Eigener Datenbank-Benutzer für die **schreibenden** Tools (empfohlen, siehe „Schreiben"). Nur zusammen mit `write_credential`. |
| `write_credential` | nein | **Name** des Passworts des Schreib-Benutzers im Vault. Nur zusammen mit `write_user`. |
| `filters` | nein | Filter-Slots der Integration (siehe „Filter-Slots"). |
| `timeout` | nein | Zeitlimit pro Aufruf, z. B. `10s`, `1500ms`. Default 10s, **Obergrenze 60s** (darüber: Ladefehler, keine stille Kürzung). |
| `redact_params` | nein | Liste von Parameter-Namen, deren Werte im **Audit-Log** als `[REDACTED]` erscheinen (siehe unten). |
| `tools` | ja | Liste der angebotenen Abfragen (mindestens eine). |

Es gibt bewusst **kein `min_interval`** (die Schutzmechanik sind der kleine
Verbindungs-Pool und das Statement-Timeout), **kein `endpoint_view`** und
**keine `description`** auf oberster Ebene — beides kommt, wenn es gebraucht
wird, nicht auf Vorrat.

### `connection`

| Feld | Pflicht | Bedeutung |
|---|---|---|
| `host` | ja | Name oder IP des Datenbank-Servers. |
| `port` | nein | Default `5432`. |
| `database` | ja | Name der Datenbank. **Eine Datenbank je Integration** — es gibt keinen Cross-DB-Join. |
| `user` | ja | Der Datenbank-Benutzer. **Kein Secret** — er steht absichtlich im Klartext in der Datei, damit ein Review sieht, dass hier ein **read-only-Benutzer** steht (siehe Rezept unten). |
| `sslmode` | **ja** | `disable`, `require`, `verify-ca` oder `verify-full`. |

**`sslmode` hat bewusst keinen Default und es gibt bewusst kein `prefer`.** Der
libpq-Modus `prefer` versucht TLS und fällt bei Ablehnung **stillschweigend** auf
eine unverschlüsselte Verbindung zurück — das ist gelogene Sicherheit. Wer im
lokalen Netz unverschlüsselt fahren will, schreibt `disable` hin und sieht es
beim nächsten Review. Für eine Verbindung über Netzgrenzen ist `verify-full`
richtig (`require` verschlüsselt, prüft aber das Zertifikat nicht).

Host, Datenbank und Benutzer dürfen **keine Leerzeichen, Anführungszeichen,
Backslashes oder Steuerzeichen** enthalten — sie wandern in die
Verbindungskonfiguration des Treibers, und dort hätten diese Zeichen eine
Bedeutung. In einem Hostnamen sind sie nie nötig.

Ein Feld `connection.password` gibt es **nicht**: Ein hingeschriebenes Passwort
ist ein Ladefehler mit dem Hinweis auf den Vault. Die Datei darf bedenkenlos
eingecheckt werden.

### `tools[]`

| Feld | Pflicht | Bedeutung |
|---|---|---|
| `name` | ja | Tool-Name (Kleinbuchstaben, Ziffern, Unterstrich). Eindeutig innerhalb der Integration. |
| `description` | ja | **Der wichtigste Text der ganzen Datei.** Der Agent sieht das SQL nie — er entscheidet allein hieraus, ob und wie er das Tool benutzt. Beschreibe, *was* zurückkommt (Spalten!), *welche* Filter es gibt, *Datumsformate* und wie man blättert. Englisch. |
| `params` | nein | Eingabeparameter (siehe unten). |
| `query` | ja | Die hinterlegte Abfrage mit `@name`-Platzhaltern (siehe unten). |
| `max_rows` | nein | Zeilen-Obergrenze. Default `500`, harte Obergrenze `5000`. |
| `write` | nein | `true` markiert das Tool als **schreibend** (siehe „Schreiben"). Default `false`. |
| `max_affected_rows` | nein | Nur an Schreib-Tools: Obergrenze der veränderten Zeilen. Default `1`, harte Obergrenze `1000`. |
| `privacy` | nein | Pseudonymisierung einzelner Spalten (siehe unten). |

### `params[]`

**Identisch zum REST-Connector** (dieselben Felder, dieselbe Bedeutung, dasselbe
JSON-Schema für den Agenten):

| Feld | Pflicht | Bedeutung |
|---|---|---|
| `name` | ja | Parametername; zugleich der Platzhalter `@name` in der Abfrage. Kleinbuchstaben, Ziffern, Unterstrich. |
| `description` | empfohlen | Beschreibung für den Agenten. |
| `type` | ja | `string`, `integer`, `number` oder `boolean`. |
| `required` | nein | `true` = Pflichtparameter. |
| `enum` | nein | Erlaubte Werte (nur bei `type: string`). |

## Die Abfrage (`query`)

### Platzhalter `@name` — es werden nur WERTE gebunden

```sql
SELECT auftrag_nr, betrag FROM wawi.auftraege WHERE kunde_nr = @kunde
```

`@kunde` wird als **echter Bind-Parameter** übergeben (Extended Query Protocol).
Der Wert wird **nie** in den SQL-Text hineingeschrieben — SQL-Injection ist hier
nicht „abgefangen", sondern strukturell nicht möglich.

Deshalb gilt auch: **Ein Parameter kann keinen Tabellen- oder Spaltennamen
liefern** und keinen Teil der Abfrage-Struktur. `ORDER BY @spalte` funktioniert
nicht (und soll es nicht). Wer nach verschiedenen Spalten sortieren will, macht
daraus zwei Tools oder einen `enum`-Parameter plus ein `CASE` in der Abfrage.

### Optionale Parameter: das NULL-Idiom

Ein weggelassener optionaler Parameter wird **als SQL NULL gebunden** — nicht
„weggelassen". Die Abfrage ist fest; ein fehlender Bind-Wert wäre eine
unvollständige Anweisung. Das Muster für „Filter nur, wenn gesetzt" lautet:

```sql
WHERE (@status::text IS NULL OR a.status = @status)
```

Der Cast (`::text`, `::int`, `::numeric`, `::bool`) ist wichtig: PostgreSQL muss
den Typ des Platzhalters kennen, wenn er nur in einem `IS NULL` steht.

Weitere gängige Formen:

```sql
-- Bereich, beide Grenzen optional
WHERE (@von::date IS NULL OR a.datum >= @von)
  AND (@bis::date IS NULL OR a.datum <= @bis)

-- Textsuche, optional (ILIKE mit Wildcards um den Wert)
WHERE (@suche::text IS NULL OR k.kunde_name ILIKE '%' || @suche || '%')

-- Seitenweise blättern (der Agent blättert selbst über die Parameter)
ORDER BY a.datum DESC
LIMIT coalesce(@seitengroesse::int, 50)
OFFSET coalesce(@versatz::int, 0)
```

### Regeln (beim Start geprüft — die Spec lädt sonst gar nicht)

- **Genau EIN Statement.** Ein Semikolon ist ein Ladefehler — **auch das
  abschließende**, und auch eines in einem Text-Literal. Die Prüfung ist
  absichtlich stumpf: In einer hinterlegten Abfrage kostet das nichts, und die
  sichere Richtung ist wichtiger als der Komfort.
- **Der erste Token ist `SELECT` oder `WITH`** (Groß-/Kleinschreibung
  gleichgültig). Ein Kommentar **vor** der Abfrage ist deshalb ebenfalls nicht
  erlaubt — er gehört hinein, nicht davor.
- **Jeder `@name` hat einen deklarierten Parameter** und **jeder deklarierte
  Parameter kommt in der Abfrage vor.** Beide Richtungen: Ein Platzhalter ohne
  Parameter wäre zur Laufzeit unauflösbar, ein Parameter ohne Platzhalter wäre
  ein Eingabefeld, das der Agent ausfüllt und das nichts bewirkt.
- Die Abfrage ist auf 8000 Zeichen begrenzt. Was länger ist, gehört als **View**
  in die Datenbank; die Spec ruft dann die View auf (das ist ohnehin die bessere
  Bauweise: die Abfrage wird vom DBA gepflegt und getestet).
- **Die Spalten müssen eindeutig benannt sein.** Jede Zeile wird als Objekt
  `Spaltenname → Wert` ausgeliefert; zwei Spalten gleichen Namens (`a.id`,
  `b.id`) würden sich überschreiben. Das fällt beim ersten Aufruf mit einer
  klaren Meldung auf — mit `AS` umbenennen.

### Was `WITH` darf und was nicht

`WITH` (Common Table Expressions) ist erlaubt, weil es der normale Weg für eine
lesbare, mehrstufige Auswertung ist. Eine **datenverändernde** CTE
(`WITH x AS (INSERT … RETURNING …) SELECT …`) beginnt formal auch mit `WITH` und
passiert die Ladezeit-Prüfung — sie scheitert dann zur **Laufzeit** an der
read-only-Transaktion und am read-only-Benutzer. Das ist ehrlich so gemeint und
durch einen Integrationstest gegen eine echte Datenbank belegt; es ist zugleich
der Grund, warum der read-only-Benutzer nicht optional ist.

## Schreiben

Ein Tool mit `write: true` verändert Daten. Es ist **genau ein `INSERT` oder ein
`UPDATE`** — die beiden Sätze oben gelten unverändert: Der Agent sieht das SQL
nie, formuliert es nie, und seine Werte reisen ausschließlich als Bind-Parameter.

```yaml
write_user: jnpt_writer              # eigener Benutzer nur zum Schreiben
write_credential: demo-wawi-db-write # dessen Passwort im Vault

tools:
  - name: set_order_status
    description: >
      Sets the status of exactly one order and returns the updated row.
    write: true
    params:
      - { name: auftrag_nr, description: The order number., type: string, required: true }
      - { name: status, description: The new status., type: string, required: true,
          enum: [offen, bezahlt, storniert] }
    query: |
      UPDATE wawi.auftraege a
      SET status = @status
      WHERE a.auftrag_nr = @auftrag_nr
      RETURNING a.auftrag_nr, a.status
    max_affected_rows: 1
```

**Die Regeln (alle beim Start geprüft):**

- **`write: true` ⇔ erster Token `INSERT`/`UPDATE`** — in beide Richtungen. Ein
  INSERT ohne `write: true` lädt nicht (es schriebe ohne Scope-Schutz, ohne
  Write-Kennzeichen im Audit und ohne Bestätigungs-Hinweis), und ein `write: true`
  auf einem SELECT lädt auch nicht (es verlangte Rechte für nichts).
- **Kein `DELETE`, kein DDL, keine Prozeduren** — in beiden Richtungen abgewiesen.
- **Ein `UPDATE` ohne `WHERE` ist ein Ladefehler.** Es würde die ganze Tabelle
  treffen, und das ist fast immer ein Unfall. Wer es wirklich meint, schreibt
  **`WHERE true`** hin — dann steht die Absicht da und ein Review sieht sie.
- **`RETURNING` ist erlaubt und empfohlen** („was habe ich gerade geschrieben").
  Das Ergebnis läuft durch denselben Weg wie eine Leseantwort: Deckel,
  Typabbildung, `privacy.read` auf den Spaltennamen.
- Alle Regeln der Abfrage gelten weiter: ein Statement, kein Semikolon, `@name`
  beidseitig gedeckt, 8000 Zeichen.

### `max_affected_rows` — der Deckel, der zurückrollt

Default **1**, harte Obergrenze **1000**. Verändert der Aufruf mehr Zeilen als
erlaubt, wird die Transaktion **zurückgerollt** und der Aufruf scheitert:

```
der Aufruf hätte 42 Zeilen verändert, erlaubt sind höchstens max_affected_rows=1
— es wurde NICHTS geschrieben (die Transaktion wurde zurückgerollt). Die
Bedingung enger fassen, sodass sie genau die gemeinten Datensätze trifft.
```

**Es gibt kein Teilschreiben.** Das ist derselbe Gedanke wie beim Zeilen-Deckel
beim Lesen, nur schärfer: Ein halb geschriebener Zustand wäre schlimmer als ein
Fehler, weil niemand ihn bemerkt.

**Keine Retries.** Ein Wiederholungsversuch schriebe ein zweites Mal. Auch der
unklare Ausgang „COMMIT abgesetzt, Antwort verloren" wird **nicht** wiederholt:
Dann meldet der Aufruf einen Fehler, obwohl geschrieben wurde, und sagt das auch.
Im Zweifel im Zielsystem nachsehen — das ist die ehrliche Seite dieses Schnitts.

### Schreib-Benutzer anlegen (Minimalrezept)

Der Schreib-Benutzer bekommt **kein SELECT-Pauschalrecht** und `INSERT`/`UPDATE`
nur auf das, was die Schreib-Tools wirklich anfassen — spaltengenau, wo möglich:

```sql
-- 1. Eigene Rolle, ohne jede Sonderberechtigung
CREATE ROLE jnpt_writer LOGIN PASSWORD 'hier-ein-langes-zufalls-passwort';

-- 2. Verbinden auf die eine Datenbank erlauben
GRANT CONNECT ON DATABASE wawi TO jnpt_writer;
GRANT USAGE ON SCHEMA wawi TO jnpt_writer;

-- 3. Nur die Spalten, die ein Schreib-Tool ändert
GRANT UPDATE (status) ON wawi.auftraege TO jnpt_writer;

-- 4. Ein UPDATE mit WHERE braucht Leserecht auf die Bedingungs-Spalten
--    (und auf die Spalten eines RETURNING) — tabellen-/spaltengenau, nie pauschal
GRANT SELECT (auftrag_nr, mandant_id, status) ON wawi.auftraege TO jnpt_writer;

-- 5. Für ein einfügendes Tool
-- GRANT INSERT (hinweis, auftrag_nr) ON wawi.hinweise TO jnpt_writer;
```

Danach das Passwort in den Vault:

```bash
printf '%s' 'hier-ein-langes-zufalls-passwort' | jnpt credential set --name demo-wawi-db-write
```

**Warum ein zweiter Benutzer?** Weil sonst die wichtigste Zusage der Lese-Seite
verloren geht. Mit getrennten Benutzern gilt weiterhin: *Der Lese-Zugang KANN
nicht schreiben* — das hält auch gegen einen Fehler in JanuaPort.

### Ein-Benutzer-Betrieb (wenn es nicht anders geht)

`write_user`/`write_credential` sind **optional**. Lässt man beide weg, laufen die
Schreib-Tools über `connection.user`. JanuaPort benutzt dafür trotzdem eine
eigene, zweite Verbindung (read-write), sodass die Lese-Tools mechanisch
unverändert in ihrer read-only-Session und ihrer `BEGIN READ ONLY`-Transaktion
laufen.

**Ehrlich gesagt, was dabei verloren geht:** **Linie 1 der Lese-Seite entfällt.**
„Diese Integration kann nicht schreiben" gilt dann nur noch auf
Transaktions-Ebene, nicht mehr auf GRANT-Ebene — ein Fehler in JanuaPort wäre
nicht mehr durch die Datenbank aufgehalten. `jnpt database check` benennt das mit
einer `[warn]`-Zeile. Die Empfehlung bleibt die Trennung.

Ladefehler bleiben in jedem Fall: `write_user` ohne `write_credential` (und
umgekehrt) sowie beide ohne ein einziges Schreib-Tool (ein totes Feld, das
aussähe, als könnte diese Integration schreiben).

### Berechtigung, Bestätigung, Audit

- **Ein integrations-weiter Scope erfasst ein Schreib-Tool NIE.** `demo-wawi`
  gibt alle **lesenden** Tools frei; zum Schreiben braucht es den tool-genauen
  Eintrag `demo-wawi:set_order_status`. Sonst wüchse ein per Update
  hinzukommendes Schreib-Tool still in eine bestehende Pauschal-Vergabe hinein.
- **Annotations:** `readOnlyHint: false`, `idempotentHint: false`,
  `openWorldHint: true`. `destructiveHint` unterscheidet die beiden Arten:
  **INSERT → `false`** (additiv), **UPDATE → `true`** (überschreibt einen
  bestehenden Wert). Ein Client kann daraus eine Rückfrage an den Menschen bauen
  — die echte Leitplanke ist aber serverseitig.
- **Jeder Schreib-Aufruf wird als Mutation protokolliert** (`write`-Kennzeichen im
  Audit), auch ein gescheiterter.

### Ergebnis eines Schreib-Tools

Mit `RETURNING` wie eine Leseantwort: `{"rows": [...]}`. Ohne `RETURNING`:

```json
{"affected": 1}
```

## Filter-Slots

Ein **Filter** ist ein SQL-Fragment, das EINMAL an der Integration gesetzt wird
und in jeder Abfrage wirkt, die ihn einsetzt:

```yaml
filters:
  - name: mandant
    sql: a.mandant_id = 1
    required: true          # jedes Tool mit WHERE MUSS ihn einsetzen

tools:
  - name: list_open_orders
    query: |
      SELECT a.auftrag_nr FROM wawi.auftraege a
      WHERE a.kunde_nr = @kunde AND {filter:mandant}
```

- **Eingesetzt wird beim Start**, nicht zur Laufzeit. Danach ist die Abfrage
  wieder eine feste Zeichenkette aus der Datei, und **alle** Prüfungen laufen auf
  diesem Stand (auch die 8000-Zeichen-Grenze). Ein Agent kann an einem Filter
  nichts drehen — zum Zeitpunkt seines Aufrufs gibt es nichts mehr zu ersetzen.
- **`required: true` ist eine Zusage, kein Versprechen:** Ein Tool, das den Slot
  nicht einsetzt, **lädt nicht**. Genau deshalb gibt es Slots statt „JanuaPort
  hängt den Filter automatisch an jedes WHERE an": Bei JOINs, Aliassen, CTEs und
  Subqueries wäre die Einfügestelle nicht sicher bestimmbar, und ein
  Sicherheitsfilter, der **manchmal** nicht greift, ist schlechter als keiner.
- **Ehrliche Grenze:** Ein `INSERT` hat kein WHERE — INSERT-Tools sind von
  `required` ausgenommen. Wer auch beim Einfügen eine Mandantengrenze braucht,
  setzt den Wert als Spalte in die INSERT-Liste oder erzwingt ihn per
  CHECK-Constraint bzw. Row-Level-Security in der Datenbank.
- **Jedes Fragment wird beim Einsetzen automatisch geklammert:** aus
  `WHERE x = 1 AND {filter:f}` mit `sql: "a = 1 OR b = 2"` wird
  `WHERE x = 1 AND (a = 1 OR b = 2)`. Ohne die Klammern bände das `OR` wegen der
  SQL-Präzedenz um das `AND` herum — der Filter griffe **still** nur auf einen
  Teil der Bedingung. Um einen booleschen Ausdruck ist die Klammer semantisch
  immer neutral; eigene Klammern im Fragment schaden nicht.
- Das Fragment ist **statisch**: kein `@name` darin (ein Filter, dessen Wert von
  einer Eingabe abhinge, wäre keine Grenze), kein Semikolon, keine
  Verschachtelung. Ein Filter, den **kein** Tool einsetzt, ist ein Ladefehler —
  er sähe aus wie eine Datengrenze und wäre keine.
- `jnpt database check` **präpariert jede zusammengesetzte Abfrage** (Stufe 4).
  Ein Alias-Fehler im Fragment (`a.mandant_id`, obwohl das Tool `auf` als Alias
  benutzt) fällt damit beim Prüfen auf und nicht beim ersten Agenten-Aufruf.

**Der Weg des DBA bleibt der bessere für komplexe Fälle:** Views und Row-Level-
Security sind dieselbe Idee eine Ebene tiefer und wirken auch dann, wenn jemand
an JanuaPort vorbei auf die Datenbank sieht.

## Read-only in drei Linien

JanuaPort verlässt sich nicht auf eine Linie:

1. **Der Datenbank-Benutzer hat nur Leserechte.** Betreiber-Pflicht, Rezept
   unten. Das ist die einzige Linie, die auch gegen einen Fehler in JanuaPort
   hält — sie ist deshalb nicht verhandelbar.
2. **Die Verbindung ist read-only.** JanuaPort setzt
   `default_transaction_read_only = on` als Session-Einstellung.
3. **Jede Abfrage läuft in `BEGIN READ ONLY`.**

PostgreSQL nennt READ ONLY selbst eine *„high-level notion of read-only"*: Es
blockiert INSERT/UPDATE/DELETE/MERGE/COPY FROM und DDL zur Laufzeit — auch aus
dem Rumpf einer VOLATILE-Funktion —, ist aber **kein Byte-Schreibschutz**.
Genau deshalb steht Linie 1 an erster Stelle.

### Read-only-Benutzer anlegen (Minimalrezept)

Als Datenbank-Administrator, EINMAL je Datenbank:

```sql
-- 1. Rolle mit Login, ohne jede Sonderberechtigung
CREATE ROLE jnpt_readonly LOGIN PASSWORD 'hier-ein-langes-zufalls-passwort';

-- 2. Verbinden auf die eine Datenbank erlauben
GRANT CONNECT ON DATABASE wawi TO jnpt_readonly;

-- 3. Nur die Schemata sichtbar machen, die JanuaPort lesen soll
GRANT USAGE ON SCHEMA wawi TO jnpt_readonly;

-- 4. Nur SELECT, und nur auf die Tabellen/Views, die gebraucht werden
GRANT SELECT ON wawi.auftraege, wawi.kunden TO jnpt_readonly;

-- 5. Optional: auch künftige Tabellen dieses Schemas nur lesend
--    (weglassen, wenn jede neue Tabelle bewusst freigegeben werden soll)
ALTER DEFAULT PRIVILEGES IN SCHEMA wawi
  GRANT SELECT ON TABLES TO jnpt_readonly;
```

Danach das Passwort in den Vault (es erscheint dort nie wieder im Klartext):

```bash
printf '%s' 'hier-ein-langes-zufalls-passwort' | jnpt credential set --name demo-wawi-db
```

**Warum tabellengenau und nicht `GRANT SELECT ON ALL TABLES`?** Weil die
Berechtigung die einzige Grenze ist, die eine falsch geschriebene Abfrage nicht
überschreiten kann. Ein `SELECT * FROM personal.gehaelter` in einer Spec, die
niemand mehr liest, ist der Fall, gegen den dieses `GRANT` schützt — nicht der
Angreifer, sondern der Alltag.

**Was der Benutzer NICHT braucht:** `SUPERUSER`, `CREATEDB`, `CREATEROLE`,
`REPLICATION`, `BYPASSRLS`, Rechte an anderen Schemata, und keinerlei
Schreibrechte. Wenn die Bestandssoftware nur einen Admin-Zugang kennt: einen
zweiten Benutzer anlegen, nicht den Admin-Zugang eintragen.

## Deckel: Zeilen, Bytes, Zeit — und warum sie Fehler sind

Drei harte Grenzen, alle **fail-closed**:

| Grenze | Default | Obergrenze | Wirkung |
|---|---|---|---|
| `max_rows` je Tool | 500 | 5000 | Zeile Nr. `max_rows + 1` bricht den Aufruf ab. |
| Ergebnisgröße | 1 MiB | — | Ein größeres serialisiertes Ergebnis bricht den Aufruf ab. |
| `timeout` je Aufruf | 10s | 60s | Server-seitiges `statement_timeout` **plus** client-seitige Frist. |

**Ein erreichter Deckel liefert einen Fehler, nie ein gekürztes Ergebnis.** Das
ist die wichtigste Entscheidung dieses Abschnitts: Eine abgeschnittene Liste
sieht wie eine vollständige aus. Der Agent würde daraus eine Summe bilden, einen
Abgleich für vollständig erklären oder „es gibt keine weiteren offenen Posten"
schließen — plausibel und falsch. Der Fehlertext ist deshalb eine
Arbeitsanweisung („Ergebnis überschreitet max_rows=200 — die Abfrage
einschränken"), und der Agent kann sie selbst befolgen, wenn die Abfrage
Filter-Parameter anbietet. **Gib deinen Tools Filter- und Seiten-Parameter** —
das ist die eigentliche Antwort auf den Deckel.

Das Zeitlimit hat zwei Seiten, weil ein Abbruch-Signal laut
PostgreSQL-Protokoll ohne Erfolgsgarantie ist („issuing a cancel simply improves
the odds"). Die harte, garantierte Grenze ist das serverseitige
`statement_timeout`; die Client-Frist kommt dazu, damit der Gateway nicht an
einer Verbindung klebt, die gar nicht mehr antwortet.

## Was der Agent bekommt (Ergebnisform und Typen)

Das Ergebnis ist ein **JSON-Objekt mit dem Schlüssel `rows`**; darin steht ein
Objekt je Zeile, Spaltenname → Wert:

```json
{"rows": [
  {"auftrag_nr": "A-2026-0001", "datum": "2026-01-14T00:00:00Z", "betrag": 1234.56,
   "status": "offen", "kunde_name": "‹name-7f3a91b2c4d5e6f708192a3b›"}
]}
```

**Warum die Hülle?** Weil die MCP-Spezifikation `structuredContent` als *„an
optional JSON object"* definiert. Eine Liste auf oberster Ebene ist spec-widrig:
Tolerante Clients schlucken sie, strikte verwerfen die **komplette** Antwort —
das Tool ist dort schlicht unbenutzbar. Ein leeres Ergebnis kommt als
`{"rows": []}` (nie `null`): „keine Treffer" ist eine gültige Antwort und darf
nicht wie ein Fehler aussehen.

Typabbildung (bewusst entschieden, nicht zufällig):

| PostgreSQL | JSON | Anmerkung |
|---|---|---|
| `text`, `varchar`, `char` | Text | |
| `int2/int4/int8` | Zahl | |
| `numeric`, `decimal` | **exakte Dezimalzahl** | bewusst NICHT über Gleitkomma — ein Rechnungsbetrag darf nicht gerundet werden. |
| `float4/float8` | Zahl | |
| `boolean` | `true`/`false` | |
| `date`, `timestamp`, `timestamptz`, `time` | ISO-8601-Text | Eine `date`-Spalte kommt als `2026-01-14T00:00:00Z`. Wer nur das Datum will: `a.datum::text AS datum`. |
| `uuid` | kanonischer Text | |
| `json`, `jsonb` | Objekt/Array | durchgereicht. |
| `bytea` | base64-Text | **Binärinhalte gehören nicht in einen KI-Kontext** — liefere `octet_length(spalte) AS groesse` statt der Spalte. |
| Arrays (`int[]`, `text[]`) | Array | |
| `NULL` | `null` | |
| alles Übrige (`interval`, Bereichstypen, eigene Typen) | Text | Verlässlich wird es mit einem ausdrücklichen `::text`-Cast in der Abfrage. |

## Berechtigung, Sichtbarkeit, Audit

- **Deny-by-default, wie überall.** Ein Zugang sieht ein Tool nur mit passendem
  Scope: `demo-wawi` (alle Tools dieser Integration) oder
  `demo-wawi:list_open_orders` (tool-genau) — dieselbe Grammatik wie bei den
  anderen Integrationsarten, dieselben Wege (`jnpt token allow`, SSO-Basis-/
  Gruppen-/Team-Scope, Scope-Auswahl in der Admin-GUI).
- **Lesende Tools sind read-only markiert** (`readOnlyHint: true`), was einem
  Client erlaubt, sie ohne Rückfrage und parallel zu nutzen. Schreibende Tools
  sind es nicht — und ein integrations-weiter Scope erfasst sie nie (siehe
  „Schreiben").
- **Jeder Aufruf wird protokolliert** (`jnpt audit list`) — mit den
  Tool-Argumenten, nie mit dem Passwort und nie mit Zeilendaten.
- **`redact_params`** ersetzt die Werte gelisteter Parameter im Audit-Log durch
  `[REDACTED]`. Jeder Eintrag muss ein in irgendeinem Tool deklarierter
  Parameter sein — ein Tippfehler wird beim Start abgelehnt (sonst würde im
  Glauben an Schutz nichts redigiert). Eine Kundennummer, ein Suchbegriff, eine
  Personalnummer: hier hinein.

### Fehlermeldungen tragen keine Daten

Eine PostgreSQL-Fehlermeldung kann einen **Parameterwert** enthalten (`invalid
input syntax for type integer: "…"`). Der Agent, das Audit-Detail und das Log
bekommen deshalb nur die Fehlerklasse plus den SQLSTATE-Code. Den Wortlaut der
Datenbank zeigt ausschließlich der lokale Diagnose-Befehl
`jnpt database check` — und auch dort bereinigt (Passwort maskiert, eine Zeile,
längenbegrenzt).

## Pseudonymisierung (`privacy`)

Der Privacy Mode funktioniert **identisch zum REST-Connector**
([Details](connector-spec.md#privacy-mode-privacy--feld-tokenisierung-epic-78),
Hintergrund: `docs/privacy-mode.md`). Der einzige Unterschied: `field` ist hier
ein **Spaltenname** des Ergebnisses.

```yaml
    privacy:
      read:                                 # ganzer Spaltenwert → Pseudonym
        - { field: kunde_name, label: name }
      scan:                                 # nur die Muster-TREFFER im Freitext
        - { field: hinweis, patterns: [iban] }
```

- **Gleiches Label = gleiches Pseudonym**, über alle Integrationsarten hinweg.
  Genau das macht die Datenbank-Integration wertvoll: Der Agent liest eine
  Kundenliste aus der Warenwirtschaft und matcht sie gegen Belege aus der
  Buchhaltung — ohne einen einzigen Klartext-Namen zu sehen.
- **Es gibt kein `privacy.write`** — auch nicht an einem schreibenden Tool. Die
  **Rückwandlung eingehender** Pseudonyme läuft ohnehin: in **allen**
  String-Parametern, ohne Deklaration; ein Block, der das nur wiederholte, wäre
  eine zweite Wahrheit. Genau das trägt den integrations-übergreifenden Fall:
  Ein Agent liest einen Namen pseudonymisiert aus der Buchhaltung und schreibt
  ihn hier als Filterwert oder als Inhalt zurück — die Datenbank bekommt den
  Klartext als Bind-Wert, im Chat bleibt das Kürzel. Ein Agent
  kann also ein Pseudonym, das er aus einer anderen Integration hat, hier als
  Filterwert einsetzen — der Klartext geht als Bind-Wert an die Datenbank, und
  jede solche Rückwandlung wird auditiert (mit dem Pseudonym, nie dem Klartext).
- Ein unbekanntes oder verfälschtes Pseudonym scheitert den Aufruf, **bevor** die
  Datenbank gefragt wird (fail-closed).

Die Admin-GUI **zeigt** eine Datenbank-Integration seit #452: Sie erscheint in
der Integrationen-Liste (Typ `DB`), im Drill-Down mit Verbindungsangaben,
Credential-Dreiklang je Richtung, Filter-Slots und den hinterlegten Abfragen,
und im Anschlussplan samt ihrer Credential-Kanten. Der Anlege-Dialog hat eine
vierte Karte, die aus einem geführten Formular eine **nur-lesende** Spec-YAML
zum Copy-Paste erzeugt (plus das GRANT-Rezept unten).

**ÜBERSTEUERT wird dort nichts** — es gilt weiterhin, was in der YAML steht: Es
gibt kein Credential-Override, keinen SQL-Editor, keine Abfrage-Ausführung und
keine Prüfung aus der Oberfläche (die Live-Prüfung bleibt `jnpt database check`).
Auch die Betreiber-Übersteuerung der Privacy-Deklaration (#335/#340) gilt für
Datenbank-Tools weiterhin nicht. Die EINZIGE Schreibaktion der GUI in diesem
Umfeld ist das Anlegen eines Credential-NAMENS ohne Wert (#245).

### Bearbeiten in der GUI (#468) — Regeneration, kein Server-Schreibpfad

Seit #468 trägt der Drill-Down bei den Aktionen einen Knopf **„Bearbeiten"**. Er
öffnet **dasselbe** Anlege-Formular, vorbefüllt mit dem, was die Verwaltung über
diese Integration weiß, nimmt Ergänzungen und Änderungen entgegen und erzeugt
daraus die **vollständige neue Spec-YAML zum Kopieren**. Die Mechanik ist
unverändert die des Anlegens:

```text
Bearbeiten → YAML kopieren → Datei in <data>/databases ERSETZEN → Gateway neu
starten → jnpt database check <name>
```

**Es wird nichts serverseitig gespeichert und nichts nachgeladen.** Datenbank-
Integrationen bleiben datei-basiert und Start-Load (Scope-Grenze Epic #414);
serverseitiges Anlegen/Ändern mit Übernahme ohne Neustart ist ein eigener
Schnitt und ausdrücklich nicht Teil dieses Wegs.

**Was übernommen wird, obwohl das Formular es nicht anbietet.** Das geführte
Formular bleibt beim Anlegen nur-lesend (s. o.). Beim Bearbeiten **reicht** es
durch, was in der Datei steht: den eigenen Schreib-Benutzer, schreibende
Werkzeuge samt `max_affected_rows`, `redact_params`, die Filter-Slots und die
`privacy`-Deklaration. Diese Angaben stehen in der Oberfläche unter **„Wird
unverändert übernommen"** — geändert werden sie weiterhin von Hand in der Datei.
Neu hinzugefügte Abfragen sind lesend.

**Filter-Slots werden zurückgeschrieben.** Die Admin-Sicht zeigt die Abfrage im
komponierten Zustand (das Fragment steht geklammert darin, s. „Filter-Slots"
oben). Die Regeneration macht daraus wieder `{filter:name}` und schreibt den
`filters:`-Block mit — sonst wäre die Datei entweder nicht ladbar („ein
deklarierter Filter, den kein Tool einsetzt") oder die erzwungene Datengrenze
still verschwunden. **Achtung beim Ergänzen:** Ein Filter mit `required: true`
muss auch in einer NEU hinzugefügten, nicht-einfügenden Abfrage stehen — die
Oberfläche sagt es an, der Loader erzwingt es.

**Den Namen ändert man hier nicht nebenbei.** Er ist die Identität der
Integration (Tool-Präfix und Scope-Schlüssel `integration:tool`). Wird er im
Formular geändert, entsteht eine **zweite** Integration — die alte Datei bleibt
liegen, und erteilte Rechte auf den alten Namen gelten für den neuen nicht. Die
Oberfläche sagt das an, sobald der Name abweicht.

**Was dabei verloren geht — ehrlich benannt:** Es entsteht eine **neue Datei**.
**Kommentare, Reihenfolge und Formatierung der alten gehen verloren**; der
Inhalt nicht. Weggelassene Angaben stehen danach ausgeschrieben da (etwa
`max_rows: 500`, der Domänen-Default) — derselbe Wert, nur sichtbar. Wer seine
Kommentare behalten will, übernimmt aus der erzeugten Datei gezielt die
geänderten Stellen, statt sie zu ersetzen.

## Prüfen und betreiben

```bash
jnpt database list                  # Name, Treiber, Ziel, Benutzer, Tool-Zahl
jnpt database check                 # alle Integrationen in Stufen prüfen
jnpt database check demo-wawi       # nur eine
jnpt database selftest demo-wawi    # eine echte Abfrage gegen die echte DB
```

**`check`** prüft in vier Stufen, **bevor** jemand Zugriff bekommt:

1. **Spec gültig** (Tool-Zahl, wie viele davon schreiben, und die
   Datenbank-Benutzer beider Richtungen — sie sollen ins Auge fallen). Im
   Ein-Benutzer-Betrieb steht hier eine `[warn]`-Zeile.
2. **Credentials im Vault** vorhanden und mit Wert — **beide**, wenn ein
   Schreib-Zugang deklariert ist. Ein *vorbereitetes* Credential (angelegt, Wert
   fehlt noch) wird als solches benannt.
3. **Live-Probe `SELECT 1`**, je Richtung eine. Sie braucht keine Deklaration —
   anders als beim REST-Connector gibt es hier eine universelle, parameterlose
   Probe, deshalb hat die Datenbank-Spec **kein `check:`-Feld**. Scheitert sie,
   zeigt die Ausgabe zusätzlich die (bereinigte) Meldung der Datenbank.
4. **Jede Abfrage präparieren.** Alle Tool-Abfragen werden — mit eingesetzten
   Filter-Slots — von der Datenbank *beschrieben*, aber **nicht ausgeführt**:
   kein Zeilenwert, keine gelesene Zeile, und bei einem Schreib-Tool keine
   Änderung. Ein Tippfehler in einem Spalten- oder Alias-Namen (auch in einem
   Filter-Fragment) fällt damit hier auf und nicht beim ersten Agenten-Aufruf.

**`selftest`** ist das Live-Urteil: Es führt das erste Tool **ohne
Pflichtparameter** wirklich aus und meldet Zeilen-/Spaltenzahl und Laufzeit.
Gibt es kein solches Tool, wird der Selbsttest **übersprungen** (kein Fehler) —
plane deshalb ein billiges, parameterloses Übersichts-Tool ein (im Beispiel:
`count_orders_by_status`). Ein **leeres Ergebnis ist hier ausdrücklich KEIN
Fehler**: Null offene Aufträge sind eine gültige Antwort einer Datenbank.

Beide Befehle setzen den Exit-Code ≠ 0 bei einem Fehlschlag (skriptbar), und
beide Ausgaben sind passwort- und datenfrei.

### Betrieb

- **Start-Load, kein Hot-Reload.** Eine neue oder geänderte Datei wird beim
  nächsten Start übernommen (`docker compose restart jnpt`). Es gibt in v1 kein
  `jnpt database add` und keinen Datei-Watch.
- **Eine ungültige Spec verhindert den Start** (fail fast) — eine halb
  funktionierende Toolmenge ist schlimmer als ein klarer Abbruch. Eine **nicht
  erreichbare Datenbank verhindert den Start nicht**: Die Verbindung entsteht
  erst beim ersten Aufruf, und `jnpt database check` sagt, woran es liegt.
- **Der Verbindungs-Pool ist klein** (höchstens 4 Verbindungen, im Leerlauf
  keine). Ein Bestandssystem soll von JanuaPort nichts merken.

## Netzzugang: die Kundendatenbank steht im Kundennetz

Der häufigste Fall dieser Integrationsart ist eine Datenbank, die **nicht** aus
dem Internet erreichbar ist — und das ist gut so. Dann braucht JanuaPort einen
Netzpfad ins Kundennetz: Es läuft im Kundennetz (die JanuaPort-Box) oder über
einen expliziten Tunnel. Das ist ein eigenes Vorhaben (Issue #268) und keine
Frage dieses Formats; öffne eine Bestandsdatenbank **nicht** ins Internet, um
diese Integrationsart zu benutzen.

## Grenzen von Version 1 (ehrlich)

Bewusst nicht dabei — jeweils mit Grund, nicht aus Zeitmangel:

- **Kein DELETE, kein DDL, keine Prozeduraufrufe.** Schreiben gibt es seit v2
  (Abschnitt „Schreiben"), aber nur additiv und fortschreibend: `INSERT` und
  `UPDATE`. Löschen und Struktur-Änderungen sind nicht rückholbar und bleiben
  draußen. Und weiterhin gilt: Schreiben in eine Bestandsdatenbank umgeht die
  Geschäftslogik der Anwendung darüber — prüfe erst, ob es eine API gibt.
- **Keine Transaktion über mehrere Tools.** Jeder Aufruf ist für sich atomar;
  zwei Aufrufe sind zwei Transaktionen. Ein Geschäftsvorfall, der beide zusammen
  braucht, gehört in eine Datenbank-Funktion oder hinter eine API.
- **Keine dynamischen Filter-Fragmente.** Ein Filter-Slot ist statisch (siehe
  „Filter-Slots"); pro Konsument verengte Wertebereiche sind ein eigenes Thema.
- **Keine Schema-Erkundung durch den Agenten.** Kein `list_tables`, kein
  `describe`. Der Agent soll nicht herausfinden, was es gibt — er soll benutzen,
  was ein Mensch freigegeben hat.
- **Nur PostgreSQL.** MySQL/MariaDB und MS SQL Server sind mit reinen
  Go-Treibern machbar und vorgesehen; sie sind eine neue Datei in der Runtime,
  kein Umbau. DB2 bleibt ehrlich draußen (der offizielle Treiber braucht C-Code,
  und das statische Binary ist ein Produktversprechen).
- **Eine Datenbank je Integration.** Zwei Datenbanken = zwei Specs = zwei
  Berechtigungs-Identitäten. Kein Cross-DB-Join.
- **Keine SCHREIBENDE Verwaltungsfläche.** Seit #452 gibt es eine read-only
  Admin-REST-Sicht (`GET /api/admin/databases`) und die GUI darauf; die Specs
  selbst bleiben datei-basiert, ohne Hot-Reload und ohne Übersteuerung. Der
  Scope-Picker sah sie ohnehin schon, weil er generisch aus dem Tool-Katalog
  liest. Der Admin-MCP folgt in #448.
- **Kein `min_interval`**, keine Retries, keine Ergebnis-Zwischenspeicherung.

**Wann ist diese Integrationsart nicht das richtige Werkzeug?** Wenn das
Bestandssystem eine brauchbare API hat (dann: [REST-Connector](connector-spec.md)
— eine API ist ein Vertrag, ein Datenbankschema nicht), wenn Schreiben gebraucht
wird, oder wenn die Auswertung so komplex ist, dass sie in der Datenbank als
View bzw. in einem eigenen MCP-Server besser lebt. Im Zweifel: kleiner halten
und nachfragen.
