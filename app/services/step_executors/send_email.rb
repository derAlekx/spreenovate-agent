module StepExecutors
  class SendEmail < Base
    def execute
      project = item.pipeline.project

      smtp_config = JSON.parse(project.credential_for("smtp") || "{}")
      raise "Keine SMTP-Credentials für #{project.name}" if smtp_config.empty?

      to = item.data["email"]
      subject = item.data.dig("draft", "subject")
      body = item.data.dig("draft", "body")
      from_name = smtp_config["from_name"] || step.config["from_name"]
      from_address = smtp_config["from_address"] || step.config["from_address"]
      bcc = step.config["bcc"] || from_address

      raise "Keine Email-Adresse für Item##{item.id}" unless to.present?
      raise "Kein Draft für Item##{item.id}" unless subject.present? && body.present?
      raise "Kein from_name in SMTP-Config" unless from_name.present?
      raise "Kein from_address in SMTP-Config" unless from_address.present?

      delivery_settings = {
        address: smtp_config["host"],
        port: smtp_config["port"].to_i,
        user_name: smtp_config["user"],
        password: smtp_config["password"],
        authentication: :login,
        enable_starttls_auto: smtp_config["port"].to_i != 465,
        ssl: smtp_config["port"].to_i == 465
      }

      signature = project.settings["email_signature"]

      message = OutboundMailer.cold_email(
        to: to,
        subject: subject,
        body: body,
        from_name: from_name,
        from_address: from_address,
        bcc: bcc,
        signature: signature
      )
      message.delivery_method(:smtp, delivery_settings)
      message.deliver_now

      data = item.data.dup
      data["sent_at"] = Time.current.iso8601
      data["sent_email"] = {
        "subject" => subject,
        "body" => body,
        "sent_at" => data["sent_at"]
      }
      item.update!(data: data, status: "sent")

      item.item_events.create!(
        pipeline_step: step,
        event_type: "sent",
        note: "Email gesendet an #{to}"
      )
    end
  end
end
