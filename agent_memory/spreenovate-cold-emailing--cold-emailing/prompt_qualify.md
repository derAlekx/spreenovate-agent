# Qualify Prompt

Du bewertest, ob eine Person als Cold-Email-Empfänger für Spreenovate relevant ist.

## Über Spreenovate

Spreenovate ist ein KI-Sparringspartner für Führungskräfte in DACH-Mittelstandsfirmen. Wir helfen einzelnen Entscheidern, KI selbst zu durchdringen, indem wir gemeinsam an einem echten Problem aus deren Alltag arbeiten. Zielkunden sind Personen mit Budget-Verantwortung und Entscheidungsgewalt im Unternehmen.

## Wer ist die richtige Zielperson

**Klar relevant (Score 4-5):**
- Geschäftsführer, Managing Director, Managing Partner, Inhaber, Founder, Co-Founder
- C-Level: CEO, CFO, CTO, COO, CMO, CDO
- Bereichsleiter, Abteilungsleiter
- Director, Head of [X], VP, Vice President
- Senior Partner, Partner (in Beratung/Kanzleien)

**Edge Cases (Score 3):**
- Senior Manager (kann beides sein, je nach Firma)
- Principal (oft operativ Senior, manchmal Entscheider)
- Lead [X] (in kleinen Firmen oft Entscheider, in großen oft nicht)
- Managing Consultant
- Wenn unklar oder Title nicht eindeutig zuordenbar

**Klar nicht relevant (Score 1-2):**
- Single Contributors mit Manager-Titel ohne Lead-Bezeichnung (Marketing Manager, Account Manager, Sales Manager, HR Manager)
- Account Executive, Sales Executive
- Specialist, Coordinator, Analyst, Assistant
- Junior-Rollen
- Praktikanten, Werkstudenten, Trainees

## Eingabe

- **Name:** {{name}}
- **Titel:** {{title}}
- **Firma:** {{company}}

## Output-Format

Antworte EXAKT in diesem Format, ohne Erklärungen davor oder danach:

score: [Zahl von 1 bis 5]
reason: [Ein Satz, max 80 Zeichen, warum dieser Score]

Beispiele:

```
score: 5
reason: Geschäftsführer eines Mittelstandsunternehmens, klarer Entscheider.
```

```
score: 2
reason: Marketing Manager ohne strategische Entscheidungsbefugnis.
```

```
score: 3
reason: Senior Manager-Titel ohne klaren Hinweis auf Lead-Funktion.
```
