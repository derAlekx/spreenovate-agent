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

# Test-Items
import_step = pipeline.pipeline_steps.find_by(position: 1)
review_step = pipeline.pipeline_steps.find_by(position: 4)

unless pipeline.items.exists?
  pipeline.items.create!([
    {
      current_step: review_step,
      status: "review",
      data: {
        "name" => "Klaus Haddick",
        "email" => "haddick@dnla.de",
        "company" => "DNLA GmbH",
        "title" => "Managing Director",
        "research" => { "summary" => "DNLA entwickelt Personaldiagnostik-Tools..." },
        "draft" => { "subject" => "Wenn KI Sozialkompetenz misst", "body" => "Hallo Herr Haddick, ..." }
      }
    },
    {
      current_step: import_step,
      status: "pending",
      data: {
        "name" => "Badr Derbali",
        "email" => "badr.derbali@k-recruiting.com",
        "company" => "K-Recruiting Life Sciences",
        "title" => "Senior Recruiting Manager"
      }
    }
  ])
end
