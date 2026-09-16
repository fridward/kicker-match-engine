# kicker-match-engine — Einstieg für Coding-Agenten

Geteiltes Swift-Package im KICKER-Verbund. Es enthält die Spielsimulation — sie läuft in beiden Apps **und** im Backend (dort per Git gepinnt) und wird von der
iOS-App, der Android-App (via Skip) und teils vom Backend benutzt.

## Das gemeinsame Wissen liegt im Leit-Repo

KICKER besteht aus **neun Repos**, die nebeneinander unter `kicker_all/`
liegen. Regeln, Abläufe und Erfahrungswissen stehen **einmal** im Leit-Repo
`kicker` — nicht hier:

| Was | Wo |
|---|---|
| Einstieg + feste Regeln + Repo-Landkarte | `../kicker/AGENTS.md` |
| Arbeitsregeln (Matrix, Originaltreue, Parität) | `../kicker/docs/arbeitsregeln.md` |
| Erfahrungswissen (Index) | `../kicker/docs/wissen/MEMORY.md` |
| Abläufe (Version, Release, Deploy, Sitzungsabschluss) | `../kicker/docs/ablaeufe/` |

Liegt das Leit-Repo nicht daneben: `git clone https://github.com/fridward/kicker.git`
neben dieses Repo, dann `kicker/Scripts/kicker-all-klonen.sh`.

Antworten und Commit-Nachrichten auf Deutsch.

## Was hier besonders gilt

- **Was hier geändert wird, trifft alle Plattformen gleichzeitig** — genau
  deshalb gibt es dieses Paket. Logik gehört hierher, nicht zweimal in die Apps.
- **Skip-tauglich schreiben:** kein Combine, kein UIKit, kein `String(format:)`,
  keine untypisierten Text-Ketten, `Int64` für 64-Bit-Konstanten. Der Katalog:
  `../kicker/docs/bereiche/android.md`.
- **Die Mechanik ist ein Port aus `KICKER.BAS`** — Fundstelle im Code zitieren,
  nichts „verbessern". Zweifelsfälle: `../kicker/docs/nicht-bugs.md`.
- **`swift test` vor „fertig"** — die Paritätstests sichern unter anderem die
  Carryover-Regeln gegen Regressionen.

Alles Weitere: `../kicker/docs/bereiche/pakete.md`.
