class PipelinesController < ApplicationController
  def show
    @pipeline = Pipeline.find(params[:id])
    @items = @pipeline.items.includes(:current_step).order(created_at: :desc)
    @steps = @pipeline.pipeline_steps.order(:position)
  end

  def import_csv
    @pipeline = Pipeline.find(params[:id])

    unless params[:csv_file].present?
      redirect_to @pipeline, alert: "Bitte CSV-Datei auswählen."
      return
    end

    csv_content = params[:csv_file].read.force_encoding("UTF-8")

    # Apollo-CSV hat First Name / Last Name getrennt — zusammenbauen
    lines = CSV.parse(csv_content, headers: true)
    merged_csv = CSV.generate do |out|
      out << ["name", "email", "company", "title"]
      lines.each do |row|
        name = [row["First Name"], row["Last Name"]].compact.join(" ")
        out << [name, row["Email"], row["Company Name"], row["Title"]]
      end
    end

    result = StepExecutors::CsvImport.import(
      pipeline: @pipeline,
      csv_content: merged_csv
    )

    redirect_to @pipeline,
      notice: "#{result[:imported]} Kontakte importiert, #{result[:skipped]} Duplikate übersprungen."
  end
end
