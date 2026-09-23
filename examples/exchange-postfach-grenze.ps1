# JanuaPort — Exchange-Grenze: die Postfach-App darf GENAU EIN Postfach erreichen.
# Beilage zu docs/connector-microsoft-graph-mail.md, Schritt 4, Variante A (RBAC).
# Bewährt im Showcase-Neuaufbau am 13.08.2026.
#
# VOR DEM START die drei Werte eintragen:
#   $AppId    — Anwendungs-ID der Postfach-App (App-Registrierung → Übersicht)
#   $ObjId    — Objekt-ID der UNTERNEHMENSANWENDUNG (Entra → Unternehmensanwendungen
#               → eure Postfach-App → Übersicht). NICHT die der App-Registrierung!
#   $Postfach — SMTP-Adresse des EINEN erlaubten (freigegebenen) Postfachs
#
# NACH DEM LAUF (Pflicht, sonst ist die Grenze wirkungslos): In der App-Registrierung
# die mandantenweite Mail.ReadWrite-Berechtigung ENTFERNEN — Entra- und
# Exchange-Rechte ADDIEREN sich. Der App-Token wird auch ohne Entra-Zustimmung
# ausgestellt (live belegt); die Rechte kommen dann allein aus Exchange.
#
# Wirkung: 30 Minuten bis 2 Stunden Microsoft-Propagation einplanen. Die Anlage
# cacht ihren App-Token bis Ablauf — nach der Umstellung einmal neu starten.

$ErrorActionPreference = "Stop"
$AppId    = "<ANWENDUNGS-ID>"
$ObjId    = "<OBJEKT-ID-DER-UNTERNEHMENSANWENDUNG>"
$Postfach = "<postfach@example.com>"
$Verboten = "<ein-anderes-EXISTIERENDES-postfach@example.com>"  # fuer die Gegenprobe

if (-not (Get-Module -ListAvailable ExchangeOnlineManagement)) {
    Write-Host "Exchange-Online-Modul wird einmalig installiert (Nachfragen mit J/Y bestaetigen)..."
    # -AllowClobber: auf Rechnern mit Anaconda/alternativen Paket-Kommandos schlaegt
    # die Installation sonst mit "CommandAlreadyAvailable" fehl (live gefunden).
    Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber
}
Import-Module ExchangeOnlineManagement

Write-Host "Jetzt oeffnet sich die Microsoft-Anmeldung im Browser - mit dem Admin-Konto anmelden."
Connect-ExchangeOnline -ShowBanner:$false

# Schritt 0 (einmalig je Tenant): Ohne diese Freischaltung lehnt Exchange eigene
# Scopes/Rollenzuweisungen ab ("derzeit nicht zulaessig") - JEDER frische Tenant
# haengt genau hier (live gefunden 13.08.2026). Microsoft braucht nach dem
# Freischalten einige Minuten; scheitern A/B danach noch, spaeter NOCHMAL laufen
# lassen - das Skript ist wiederholbar.
try { Enable-OrganizationCustomization -ErrorAction Stop; Write-Host "Organisations-Anpassung freigeschaltet (Microsoft braucht ggf. Minuten)." }
catch { Write-Host ("Freischaltung: " + $_.Exception.Message) }

try {
    New-ServicePrincipal -AppId $AppId -ObjectId $ObjId -DisplayName "JanuaPort Postfachzugriff" -ErrorAction Stop | Out-Null
    Write-Host "Schritt 1/3: Dienstprinzipal angelegt."
} catch { if ($_.Exception.Message -match "exist|bereits|vorhanden|duplicate") { Write-Host "Schritt 1/3: existiert schon - in Ordnung." } else { Write-Host ("Schritt 1/3 FEHLER (Wortlaut): " + $_.Exception.Message) } }

try {
    New-ManagementScope -Name "JanuaPort Postfach-Scope" -RecipientRestrictionFilter "PrimarySmtpAddress -eq '$Postfach'" -ErrorAction Stop | Out-Null
    Write-Host "Schritt 2/3: Scope (genau ein Postfach) angelegt."
} catch { if ($_.Exception.Message -match "exist|bereits|vorhanden|duplicate") { Write-Host "Schritt 2/3: existiert schon - in Ordnung." } else { Write-Host ("Schritt 2/3 FEHLER (Wortlaut): " + $_.Exception.Message) } }

try {
    New-ManagementRoleAssignment -App $ObjId -Role "Application Mail.ReadWrite" -CustomResourceScope "JanuaPort Postfach-Scope" -ErrorAction Stop | Out-Null
    Write-Host "Schritt 3/3: Rolle mit diesem Scope zugewiesen."
} catch { if ($_.Exception.Message -match "exist|bereits|vorhanden|duplicate") { Write-Host "Schritt 3/3: existiert schon - in Ordnung." } else { Write-Host ("Schritt 3/3 FEHLER (Wortlaut): " + $_.Exception.Message) } }

Write-Host ""
Write-Host "===== GEGENPROBE (InScope: erste Zeile True, zweite False) ====="
Test-ServicePrincipalAuthorization -Identity $ObjId -Resource $Postfach | Format-Table | Out-String | Write-Host
Test-ServicePrincipalAuthorization -Identity $ObjId -Resource $Verboten | Format-Table | Out-String | Write-Host

Disconnect-ExchangeOnline -Confirm:$false
Write-Host "Fertig. Jetzt die Entra-Berechtigung Mail.ReadWrite entfernen (Kopf dieses Skripts)."
