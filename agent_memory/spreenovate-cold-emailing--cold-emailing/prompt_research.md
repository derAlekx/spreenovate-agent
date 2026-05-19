# Research Prompt

Recherchiere diese Person für personalisierten B2B-Outreach.

## Was du herausfinden sollst

1. **Firma:** Was machen die konkret? Produkt/Service, Branche, Größe wenn findbar. Nicht die "Über uns"-Floskel, sondern was sie wirklich tun.
2. **Person:** Welche Rolle hat sie? Entscheider, Technik, Business? Was ist ihr Verantwortungsbereich? Was machen die tägliche Arbeit solcher Personen aus?
3. **Aktuelles:** Gibt es News zur Firma? Funding, Launches, Hiring, neue Kunden, Probleme, Restrukturierung?
4. **Pain Points:** Was könnte diese Person in ihrer Rolle aktuell beschäftigen? Wo drückt der Schuh?
5. **Hook:** Gibt es etwas Konkretes, das als Aufhänger für eine Email taugt? Etwas Spezifisches, nicht Generisches.

## Kontext: Wer wir sind und wen wir ansprechen

Absender: Spreenovate — zwei AI-Consultants (Fabian & Alexander, Berlin) im Abo-Modell, helfen Unternehmen KI zu verstehen und eigenständig einzusetzen. Kein Tool-Verkauf, keine Agentur.

Zielgruppe: Heads of, GFs, Teamleiter in DACH-Mittelstandsunternehmen, die KI-Verantwortung tragen aber nicht genau wissen wo anfangen.

Besonders relevante Anknüpfungspunkte:
- Digitalisierung, KI-Einsatz oder KI-Strategie im Unternehmen
- Unsicherheit/FOMO beim Thema KI ("wir sollten was machen, aber...")
- Gescheiterte oder halbherzige KI-Versuche
- Manuelle Prozesse die offensichtlich automatisierbar wären
- Wettbewerbsdruck durch KI-affine Konkurrenten

## Skip-Signal (WICHTIG, zuerst prüfen!)

Falls du während der Recherche auf einen der folgenden Sachverhalte stößt, BEGINNE den Output mit `SKIP: [kurzer Grund]` und brich ab. Kein Research-Text danach nötig.

Skip-Gründe:
1. **Person verstorben** — Nachruf, Sterbeanzeige, "in memoriam", o.ä.
2. **Person nicht mehr in der Firma** — Wechsel, Ruhestand, Ausstieg (nur wenn klar belegt; "LinkedIn zeigt neue Rolle" reicht nicht)
3. **Firma insolvent / nicht mehr aktiv** — Insolvenz-Anzeige, Firma aufgelöst, Website offline
4. **Firma macht selbst KI als Kerngeschäft** — KI-Tool-Anbieter, KI-Beratung, KI-SaaS, generative-AI-Plattform, KI ist zentraler Bestandteil des Geschäftsmodells. Diese Firmen sind schlechter Fit für Spreenovate, weil sie KI-Kompetenz selbst aufbauen oder verkaufen. Ausnahme: Firma nutzt KI am Rand (z.B. ChatGPT-Plugin), ist aber in einer anderen Branche primär — dann kein Skip.

Beispiele:
- `SKIP: Kathrin von Hardenberg ist im April 2025 verstorben (private-banking-magazin.de, Mai 2025).`
- `SKIP: BERA GmbH ist ein KI-Beratungshaus, schlechter Fit für Spreenovate (Website bera.de).`
- `SKIP: Firma wurde 2024 aufgelöst, HRB-Eintrag gelöscht.`

Wenn kein Skip-Grund zutrifft, ignoriere diese Sektion und schreibe normalen Research-Output.

## Output

Fließtext, kein Bullshit, nur was für eine personalisierte Email nützlich ist. Keine Meta-Kommentare ("Ich recherchiere..."), keine Bold-Headers, keine Aufzählungszeichen, keine Markdown-Formatierung. Einfach Sätze hintereinander weg.

Wenn du nichts Relevantes findest, sag das, lieber ehrlich als aufgeblasen.

Gib zu jeder Erkenntnis die Quelle an: URL und Veröffentlichungsdatum falls erkennbar. Format: "...[Aussage]... (Quelle: URL, Datum)". Die Quellenangaben zählen nicht zum eigentlichen Text.

---

## Kontakt

- **Person:** {{name}}
- **Titel:** {{title}}
- **Firma:** {{company}}
- **Email:** {{email}}

## WICHTIG: Aktualität

Wir haben aktuell {{current_date}}. Nutze NUR Informationen die aus den letzten 2 Monaten stammen (ab {{min_date}}). Ältere Quellen sind wertlos — eine Email die auf veraltete News referenziert wirkt peinlich, nicht personalisiert. Wenn du nichts Aktuelles findest, sag das lieber ehrlich.
