class ProjectWizardController < ApplicationController
  before_action :ensure_wizard_state, only: [:step2, :save_step2, :step3, :save_step3, :step4, :finish]

  # GET /projects/wizard — Step 1: Projekt anlegen
  def step1
    session[:project_wizard] ||= { "step" => 1, "project" => {}, "credential_assignments" => [], "pipeline" => {}, "pipeline_steps" => [] }
    @wizard = session[:project_wizard]
  end

  # POST /projects/wizard/step1
  def save_step1
    if params[:name].blank?
      redirect_to wizard_projects_path, alert: "Projektname ist erforderlich."
      return
    end

    session[:project_wizard] ||= { "step" => 1, "project" => {}, "credential_assignments" => [], "pipeline" => {}, "pipeline_steps" => [] }
    session[:project_wizard]["project"] = { "name" => params[:name] }
    session[:project_wizard]["step"] = 2
    redirect_to wizard_step2_projects_path
  end

  # GET /projects/wizard/step2 — Credentials zuweisen
  def step2
    @wizard = session[:project_wizard]
    @credentials = Credential.order(:key)
  end

  # POST /projects/wizard/step2
  def save_step2
    assignments = []
    (params[:assignments] || []).each do |a|
      next if a[:credential_id].blank? || a[:role].blank?
      assignments << { "credential_id" => a[:credential_id].to_i, "role" => a[:role] }
    end
    session[:project_wizard]["credential_assignments"] = assignments
    session[:project_wizard]["step"] = 3
    redirect_to wizard_step3_projects_path
  end

  # GET /projects/wizard/step3 — Pipeline konfigurieren
  def step3
    @wizard = session[:project_wizard]
  end

  # POST /projects/wizard/step3
  def save_step3
    if params[:pipeline_name].blank?
      redirect_to wizard_step3_projects_path, alert: "Pipeline-Name ist erforderlich."
      return
    end

    session[:project_wizard]["pipeline"] = { "name" => params[:pipeline_name] }

    steps = []
    (params[:steps] || []).each_with_index do |s, i|
      next if s[:name].blank? || s[:step_type].blank?
      config = s[:config].present? ? (JSON.parse(s[:config]) rescue {}) : {}
      steps << { "name" => s[:name], "step_type" => s[:step_type], "position" => i + 1, "config" => config }
    end
    session[:project_wizard]["pipeline_steps"] = steps
    session[:project_wizard]["step"] = 4
    redirect_to wizard_step4_projects_path
  end

  # GET /projects/wizard/step4 — Zusammenfassung
  def step4
    @wizard = session[:project_wizard]
    credential_ids = @wizard["credential_assignments"].map { |a| a["credential_id"] }
    @credentials_map = Credential.where(id: credential_ids).index_by(&:id)
  end

  # POST /projects/wizard/finish — Alles in einer Transaction erstellen
  def finish
    wizard = session[:project_wizard]

    ActiveRecord::Base.transaction do
      @project = Project.create!(
        name: wizard["project"]["name"],
        settings: {}
      )

      wizard["credential_assignments"].each do |assignment|
        ProjectCredential.create!(
          project: @project,
          credential_id: assignment["credential_id"],
          role: assignment["role"]
        )
      end

      @pipeline = Pipeline.create!(
        project: @project,
        name: wizard["pipeline"]["name"]
      )

      wizard["pipeline_steps"].each do |step_data|
        PipelineStep.create!(
          pipeline: @pipeline,
          name: step_data["name"],
          step_type: step_data["step_type"],
          position: step_data["position"],
          config: step_data["config"] || {}
        )
      end
    end

    session.delete(:project_wizard)
    redirect_to pipeline_path(@pipeline), notice: "Projekt '#{@project.name}' erfolgreich erstellt!"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to wizard_step4_projects_path, alert: "Fehler: #{e.message}"
  end

  # DELETE /projects/wizard — Abbrechen
  def cancel
    session.delete(:project_wizard)
    redirect_to projects_path, notice: "Wizard abgebrochen."
  end

  private

  def ensure_wizard_state
    unless session[:project_wizard].present?
      redirect_to wizard_projects_path, alert: "Bitte starte den Wizard von vorne."
    end
  end
end
