# Neighbr – Testversion

Nachbarschaftshilfe als Web-App: Leistungen anbieten und buchen (z. B. Möbel aufbauen, Laub sammeln, Transport) und Dinge aus der Nachbarschaft mieten (Rasenmäher, Bohrmaschine, Staubsauger …).

**Link zum Testen:** https://kamyabd.github.io/neighbr/

## Was das ist
- Eine **Testversion**: Zahlungen, SMS-Codes und Ausweis-Check werden nur simuliert. Bitte keine echten Daten eingeben.
- Alle Daten bleiben **nur auf dem eigenen Gerät** (im Browser gespeichert). Tester sehen sich gegenseitig nicht. Für eine gemeinsame Testwelt braucht es später einen Server (z. B. Supabase).
- Installierbar: Auf Android in Chrome erscheint „Installieren“, auf dem iPhone in Safari **Teilen → Zum Home-Bildschirm**. Danach startet Neighbr wie eine App, auch offline.

## Dateien
| Datei | Zweck |
|---|---|
| `index.html` | Die komplette App |
| `vendor.js` | React (MIT-Lizenz, siehe `LICENSE-react.txt`) und ein kleiner Template-Helfer |
| `manifest.webmanifest` | Name, Farben, Symbole für „Zum Home-Bildschirm“ |
| `sw.js` | Offline-Modus (Service Worker) |
| `icons/` | App-Symbole |

## Vor einer öffentlichen Veröffentlichung
Die Platzhalter im Impressum und in der Datenschutzerklärung (in der App unter Profil › Rechtliches) müssen ausgefüllt und die Rechtstexte anwaltlich geprüft werden.
