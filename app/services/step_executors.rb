module StepExecutors
  def self.for(step_type)
    {
      "csv_import"    => StepExecutors::CsvImport,
      "ai_agent"      => StepExecutors::AiAgent,
      "human_review"  => StepExecutors::HumanReview,
      "send_email"    => StepExecutors::SendEmail,
    }.fetch(step_type) { raise "Unknown step_type: #{step_type}" }
  end
end
