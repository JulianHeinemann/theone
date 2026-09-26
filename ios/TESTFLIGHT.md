# Restwert auf TestFlight bringen

Gebaut, signiert und hochgeladen wird automatisch auf einem Mac in der Cloud (GitHub Actions, Workflow **TestFlight**).
Einmalig brauchst du dafür vier Dinge von Apple. Ein eigener Mac ist dafür nicht nötig.

## 1. Apple Developer Program

TestFlight setzt die kostenpflichtige Mitgliedschaft voraus (99 € pro Jahr): <https://developer.apple.com/programs/enroll/>.
Die Freischaltung dauert meist wenige Stunden bis zwei Tage.

**Team ID** notieren: <https://developer.apple.com/account> → Mitgliedschaft → „Team ID“ (10 Zeichen, z. B. `AB12CD34EF`).

## 2. App in App Store Connect anlegen

<https://appstoreconnect.apple.com> → Apps → **+** → Neue App:

- Plattform: iOS
- Name: **Restwert**. Ist der Name vergeben, einen Zusatz wählen, z. B. „Restwert – Gutscheine“.
- Primäre Sprache: Deutsch
- Bundle-ID: neu registrieren, z. B. `de.deinname.restwert`. `de.restwert.app` geht nur, wenn sie noch frei ist.
- SKU: beliebig, z. B. `restwert-ios`

## 3. API-Schlüssel erstellen

App Store Connect → Benutzer und Zugriff → **Integrationen** → App Store Connect API → Team-Schlüssel → **+**:

- Name: `GitHub TestFlight`
- Zugriff: **Admin**. Das ist nötig, damit die Signier-Zertifikate automatisch erstellt werden können.

Danach notieren:
- **Issuer ID**: steht oben auf der Seite.
- **Key ID**: steht in der Zeile des Schlüssels.
- **AuthKey_XXXX.p8**: einmalig herunterladen. Die Datei kann nur ein einziges Mal geladen werden.

## 4. In GitHub eintragen

Repository → Settings → Secrets and variables → Actions.

**Secrets** (Tab „Secrets“ → „New repository secret“):

| Name | Inhalt |
|---|---|
| `APPLE_TEAM_ID` | Team ID aus Schritt 1 |
| `ASC_ISSUER_ID` | Issuer ID aus Schritt 3 |
| `ASC_KEY_ID` | Key ID aus Schritt 3 |
| `ASC_KEY_P8` | kompletter Inhalt der `.p8`-Datei, inklusive `-----BEGIN PRIVATE KEY-----` |

**Variable** (Tab „Variables“ → „New repository variable“):

| Name | Inhalt |
|---|---|
| `BUNDLE_ID` | die Bundle-ID aus Schritt 2 |

## 5. Hochladen

GitHub → **Actions** → **TestFlight** → **Run workflow**. Alternativ ein Tag pushen, z. B. `git tag v1.0.0 && git push --tags`.

Nach etwa 10 Minuten ist der Build hochgeladen. Apple verarbeitet ihn danach noch 5–15 Minuten. Dann:

- **Intern testen:** App Store Connect → Restwert → TestFlight → Interne Tests → Gruppe anlegen und dich hinzufügen.
  Auf dem iPhone die App **TestFlight** installieren und die Einladung annehmen.
- **Extern testen** (Freunde, bis 10.000 Personen): externe Gruppe anlegen. Der erste Build geht durch eine kurze Beta-Prüfung bei Apple.
  Dafür werden eine Datenschutz-URL und eine Kontakt-E-Mail verlangt.
  Die URL ist `https://api-production-9130.up.railway.app/datenschutz`. Vorher dort Name und Adresse eintragen, siehe `server/public/datenschutz.html`.

Jeder Lauf erhöht die Build-Nummer automatisch. Die Version (1.0) steht in Xcode unter „Marketing Version“.
