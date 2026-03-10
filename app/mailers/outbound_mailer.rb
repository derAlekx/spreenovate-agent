class OutboundMailer < ApplicationMailer
  def cold_email(to:, subject:, body:, from_name:, from_address:, bcc: nil, signature: nil)
    @body = body
    @signature = signature

    mail(
      to: to,
      from: "#{from_name} <#{from_address}>",
      subject: subject,
      bcc: bcc
    )
  end
end
