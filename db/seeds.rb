project = Project.find_or_create_by!(name: "spreenovate") do |p|
  p.settings = { "timezone" => "Europe/Berlin" }
end

pipeline = project.pipelines.find_or_create_by!(slug: "cold-emailing") do |p|
  p.name = "Cold Emailing"
end

if pipeline.pipeline_steps.empty?
  pipeline.pipeline_steps.create!([
    { name: "Import",   step_type: "csv_import",    position: 1, config: {} },
    { name: "Research", step_type: "ai_agent",      position: 2, config: { "model" => "claude-opus-4-6-20250219", "task" => "research", "enable_web_search" => true } },
    { name: "Draft",    step_type: "ai_agent",      position: 3, config: { "model" => "claude-opus-4-6-20250219", "task" => "draft", "uses_memory" => true } },
    { name: "Review",   step_type: "human_review",  position: 4, config: {} },
    { name: "Send",     step_type: "send_email",    position: 5, config: { "from_address" => "alexander@spreenovate.de" } }
  ])
end

# Test-Items für Phase 3 Review UI
import_step = pipeline.pipeline_steps.find_by(position: 1)
review_step = pipeline.pipeline_steps.find_by(position: 4)

unless pipeline.items.exists?
  pipeline.items.create!([
    {
      current_step: review_step,
      status: "review",
      data: {
        "name" => "Klaus Haddick",
        "email" => "haddick@mailinator.com",
        "company" => "DNLA GmbH",
        "title" => "Managing Director",
        "research" => {
          "summary" => "DNLA entwickelt Personaldiagnostik-Tools zur Messung von Soft Skills und sozialer Kompetenz. Das Verfahren wird seit über 20 Jahren in HR-Abteilungen eingesetzt.",
          "pain_points" => ["KI-basierte Assessment-Konkurrenz", "Skalierung des Vertriebsteams"],
          "hook_angle" => "Sein eigenes Produkt vs. KI-Assessments"
        },
        "draft" => {
          "subject" => "Wenn KI Sozialkompetenz misst — Konkurrenz oder Ergänzung?",
          "body" => "Hallo Herr Haddick,\n\nich habe gesehen, dass DNLA seit Jahren Sozialkompetenz messbar macht. Spannend.\n\nMit dem Aufkommen von KI-basierten Assessments stellt sich die Frage: Ergänzung oder Konkurrenz?\n\nIch helfe Unternehmen wie Ihrem, KI strategisch einzusetzen — nicht als Ersatz, sondern als Verstärker.\n\nHätten Sie Lust auf einen kurzen Austausch?\n\nBeste Grüße\nAlexander Kamphorst"
        }
      }
    },
    {
      current_step: review_step,
      status: "review",
      data: {
        "name" => "Maria Schmidt",
        "email" => "maria.schmidt@mailinator.com",
        "company" => "HR Tools GmbH",
        "title" => "Head of Product",
        "research" => {
          "summary" => "HR Tools GmbH entwickelt SaaS-Lösungen für digitales Recruiting und Bewerbermanagement.",
          "pain_points" => ["KI-Integration in bestehende Software", "Wettbewerb mit größeren Anbietern"],
          "hook_angle" => "KI-Features als Differenzierungsmerkmal"
        },
        "draft" => {
          "subject" => "KI im Recruiting — Hype oder Hebel?",
          "body" => "Hallo Frau Schmidt,\n\nHR Tools digitalisiert Recruiting — aber nutzen Sie schon KI für Candidate Scoring oder automatisierte Vorauswahl?\n\nViele HR-SaaS-Anbieter stehen gerade vor der Frage: Selbst bauen oder integrieren?\n\nIch unterstütze Unternehmen dabei, KI-Workflows pragmatisch umzusetzen.\n\nKurzer Call nächste Woche?\n\nBeste Grüße\nAlexander Kamphorst"
        }
      }
    },
    {
      current_step: review_step,
      status: "review",
      data: {
        "name" => "Thomas Weber",
        "email" => "thomas@mailinator.com",
        "company" => "Startup.io",
        "title" => "CTO",
        "research" => {
          "summary" => "Startup.io ist eine Plattform für Gründer mit Fokus auf Tech-Startups im DACH-Raum.",
          "pain_points" => ["Skalierung von Content-Produktion", "Automatisierung interner Prozesse"]
        },
        "draft" => {
          "subject" => "KI-Workflows für Startups — ohne eigenes ML-Team",
          "body" => "Hallo Herr Weber,\n\nals CTO von Startup.io wissen Sie: KI ist kein Nice-to-have mehr.\n\nAber nicht jedes Startup hat ein ML-Team. Die gute Nachricht: Für 80% der Use Cases braucht man keins.\n\nIch helfe Tech-Startups, KI-Workflows mit bestehenden APIs aufzusetzen — pragmatisch und schnell.\n\nLust auf 15 Minuten?\n\nBeste Grüße\nAlexander Kamphorst"
        }
      }
    },
    {
      current_step: review_step,
      status: "approved",
      data: {
        "name" => "Lisa Berger",
        "email" => "lisa@mailinator.com",
        "company" => "E-Commerce GmbH",
        "title" => "Geschäftsführerin",
        "research" => { "summary" => "E-Commerce GmbH betreibt mehrere Online-Shops im Fashion-Bereich." },
        "draft" => {
          "subject" => "KI-Workflows für E-Commerce",
          "body" => "Hallo Frau Berger, ..."
        }
      }
    },
    {
      current_step: nil,
      status: "sent",
      data: {
        "name" => "Stefan Müller",
        "email" => "stefan@mailinator.com",
        "company" => "Digital Vikings GmbH",
        "title" => "Geschäftsführer",
        "research" => { "summary" => "Digital Vikings ist eine Digitalagentur mit Fokus auf E-Commerce und Shopify." },
        "draft" => { "subject" => "KI-Workflows für Agenturen", "body" => "Hallo Herr Müller, ..." },
        "sent_at" => "2026-03-03T08:12:00Z"
      }
    },
    {
      current_step: import_step,
      status: "pending",
      data: {
        "name" => "Badr Derbali",
        "email" => "badr.derbali@mailinator.com",
        "company" => "K-Recruiting Life Sciences",
        "title" => "Senior Recruiting Manager"
      }
    },
    {
      current_step: review_step,
      status: "rejected",
      data: {
        "name" => "Anna Kowalski",
        "email" => "anna@mailinator.com",
        "company" => "SaaS AG",
        "title" => "VP Sales",
        "research" => { "summary" => "SaaS AG bietet B2B-Software für Vertriebsteams." },
        "draft" => {
          "subject" => "Vertrieb + KI = ?",
          "body" => "Hallo Frau Kowalski, ..."
        }
      }
    }
  ])
end
