# Neighbr – Testversion

Nachbarschaftshilfe als Web-App: Leistungen anbieten und buchen (z. B. Möbel aufbauen, Laub sammeln, Transport) und Dinge aus der Nachbarschaft mieten (Rasenmäher, Bohrmaschine, Staubsauger …).

**Link zum Testen:** https://kamyabd.github.io/neighbr/

## Was das ist
- **Testphase mit echten Konten:** Anmeldung mit E-Mail und Passwort. Inserate, Chats, Buchungen und Bewertungen liegen in einer gemeinsamen Datenbank (Supabase, Server in Frankfurt) und alle sehen sie live.
- **Bezahlen ist noch simuliert:** Es fließt kein Geld über die App.
- **Identitätsprüfung:** Wird in der App angefragt und von der Betreiberin oder dem Betreiber nach einem kurzen Treffen oder Videoanruf bestätigt. Es werden keine Ausweisfotos gespeichert.
- Installierbar: Auf Android in Chrome erscheint „Installieren“, auf dem iPhone in Safari **Teilen → Zum Home-Bildschirm**. Danach startet Neighbr wie eine App, auch offline.

## Einrichtung (einmalig)
1. Supabase › **SQL Editor** › Inhalt von [`supabase/setup.sql`](supabase/setup.sql) einfügen › **Run**.
2. Supabase › **Authentication** › **Sign In / Providers** › **Email**: „Confirm email“ ausschalten (sonst schickt Supabase höchstens 2 Mails pro Stunde).
3. Supabase › **Authentication** › **URL Configuration**: Site URL `https://kamyabd.github.io/neighbr/` (wird für „Passwort vergessen“ gebraucht).
4. App öffnen, als Erste:r registrieren, dann **Profil › Ich betreibe Neighbr**. Das geht nur ein einziges Mal.

## Wer was sehen darf
| Daten | sichtbar für |
|---|---|
| Inserate, Vornamen, grünes Schild | alle mit Konto |
| Chats, Aufträge, Adressen | nur die beiden Beteiligten (und die Betreiber-Ansicht) |
| Meldungen | wer gemeldet hat und die Betreiber-Ansicht |
| Feedback, Notfälle, Anfragen zur Identitätsprüfung | nur die Betreiber-Ansicht |
| E-Mail, Handynummer, Passwort | nur die Person selbst |

Die Regeln stehen in `supabase/setup.sql` und werden von der Datenbank selbst durchgesetzt.

## Dateien
| Datei | Zweck |
|---|---|
| `index.html` | Die komplette App |
| `config.js` | Adresse der Datenbank und öffentlicher Schlüssel |
| `supabase/setup.sql` | Tabellen und Rechte für die Datenbank |
| `vendor.js` | React (MIT-Lizenz, siehe `LICENSE-react.txt`) und ein kleiner Template-Helfer |
| `manifest.webmanifest` | Name, Farben, Symbole für „Zum Home-Bildschirm“ |
| `sw.js` | Offline-Modus (Service Worker) |
| `icons/` | App-Symbole |

## Vor einer öffentlichen Veröffentlichung
Die Platzhalter im Impressum und in der Datenschutzerklärung (in der App unter Profil › Rechtliches) müssen ausgefüllt und die Rechtstexte anwaltlich geprüft werden.
