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

        item = pipeline.items.create!(
          current_step: next_step || first_step,
          status: "pending",
          data: data
        )

        item.item_events.create!(
          pipeline_step: first_step,
          event_type: "created",
          note: "CSV Import"
        )

        # Trigger processing through the pipeline
        ProcessItemJob.perform_later(item.id)

        imported += 1
      end

      { imported: imported, skipped: skipped }
    end

    private

    def self.map_columns(row_hash, mapping)
      return row_hash if mapping.empty?

      mapped = {}
      mapping.each do |csv_col, internal_col|
        mapped[internal_col] = row_hash[csv_col]
      end
      mapped
    end
  end
end
