class PipelinesController < ApplicationController
  def show
    @pipeline = Pipeline.find(params[:id])
    @steps = @pipeline.pipeline_steps.order(:position)
    @filter = params[:filter] || "review"

    @items = @pipeline.items.includes(:current_step).order(created_at: :desc)
    @items = case @filter
             when "review"     then @items.where(status: "review")
             when "processing" then @items.where(status: "processing")
             when "approved"   then @items.where(status: "approved")
             when "skipped"    then @items.where(status: "rejected")
             when "sent"       then @items.where(status: "sent")
             when "pending"    then @items.where(status: "pending")
             when "failed"     then @items.where(status: "failed")
             else @items
             end
  end

  def bulk_send
    @pipeline = Pipeline.find(params[:id])
    remaining = @pipeline.remaining_sends_today

    if remaining <= 0
      redirect_to pipeline_path(@pipeline), alert: "Tageslimit erreicht (#{@pipeline.daily_limit}/#{@pipeline.daily_limit})."
      return
    end

    send_step = @pipeline.pipeline_steps.find_by(step_type: "send_email")
    items = @pipeline.items.where(status: "approved").limit(remaining)

    count = 0
    items.find_each do |item|
      item.update!(current_step: send_step, status: "pending")
      ProcessItemJob.perform_later(item.id)
      count += 1
    end

    redirect_to pipeline_path(@pipeline),
      notice: "#{count} Emails werden gesendet..."
  end

  def test_send
    @pipeline = Pipeline.find(params[:id])
    item = @pipeline.items.where(status: "approved").first

    unless item
      redirect_to pipeline_path(@pipeline), alert: "Kein approved Item für Testmail vorhanden."
      return
    end

    project = @pipeline.project
    smtp_config = JSON.parse(project.credential_for("smtp") || "{}")

    unless smtp_config["from_address"].present?
      redirect_to pipeline_path(@pipeline), alert: "Keine SMTP-Credentials konfiguriert."
      return
    end

    test_address = smtp_config["from_address"]

    OutboundMailer.cold_email(
      to: test_address,
      subject: "[TEST] #{item.data.dig('draft', 'subject')}",
      body: item.data.dig("draft", "body"),
      from_name: smtp_config["from_name"] || "Test",
      from_address: smtp_config["from_address"]
    ).delivery_method(:smtp, {
      address: smtp_config["host"],
      port: smtp_config["port"].to_i,
      user_name: smtp_config["user"],
      password: smtp_config["password"],
      authentication: :login,
      enable_starttls_auto: smtp_config["port"].to_i != 465,
      ssl: smtp_config["port"].to_i == 465
    }).deliver_now

    redirect_to pipeline_path(@pipeline),
      notice: "Testmail gesendet an #{test_address}"
  rescue => e
    redirect_to pipeline_path(@pipeline), alert: "Testmail fehlgeschlagen: #{e.message}"
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
