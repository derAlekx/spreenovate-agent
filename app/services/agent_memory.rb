class AgentMemory
  BASE_PATH = Rails.root.join("agent_memory")

  def self.load_prompt(pipeline, task, variant: nil)
    dir = memory_dir(pipeline)

    if variant.present?
      # Explicit variant requested — NO fallback. Return empty if missing.
      # Otherwise we'd silently run variant B with variant A's prompt.
      variant_file = dir.join("prompt_#{task}_variant_#{variant}.md")
      return read_file(variant_file)
    end

    # No variant specified: load default
    read_file(dir.join("prompt_#{task}.md"))
  end

  def self.update_daily_log(pipeline, content)
    dir = memory_dir(pipeline)
    log_dir = dir.join("memory")
    FileUtils.mkdir_p(log_dir)

    log_file = log_dir.join("#{Date.current}.md")
    existing = read_file(log_file)
    new_content = existing.present? ? "#{existing}\n\n#{content}" : content
    File.write(log_file, new_content)
  end

  private

  def self.memory_dir(pipeline)
    BASE_PATH.join("#{pipeline.project.name.parameterize}--#{pipeline.slug}")
  end

  def self.read_file(path)
    File.exist?(path) ? File.read(path) : ""
  end
end
