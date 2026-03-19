module StepExecutors
  class CsvImport < Base
    def self.import(pipeline:, csv_content:, column_mapping: {})
      require "csv"

      first_step = pipeline.pipeline_steps.order(:position).first
      next_step = pipeline.pipeline_steps.order(:position).second

      imported = 0
      skipped = 0

      CSV.parse(csv_content, headers: true).each do |row|
        data = map_columns(row.to_h, column_mapping)

        if data["email"].present? &&
           pipeline.items.by_email(data["email"]).exists?
          skipped += 1
          next
        end

        begin
          item = pipeline.items.create!(
            current_step: next_step || first_step,
            status: "pending",
            data: data
          )
        rescue ActiveRecord::RecordNotUnique
          skipped += 1
          next
        end

        item.item_events.create!(
          pipeline_step: first_step,
          event_type: "created",
          note: "CSV Import"
        )

        # Kein ProcessItemJob hier — Import only, Pipeline wird manuell gestartet
        imported += 1
      end

      { imported: imported, skipped: skipped }
    end

    private

    def self.map_columns(row_hash, mapping)
      if mapping.any?
        mapped = {}
        mapping.each do |csv_col, internal_col|
          mapped[internal_col] = row_hash[csv_col]
        end
        mapped
      else
        # Keys normalisieren: "First Name" → "first_name", "Email" → "email"
        row_hash.transform_keys { |k| k.to_s.strip.downcase.gsub(/\s+/, "_") }
      end
    end
  end
end
