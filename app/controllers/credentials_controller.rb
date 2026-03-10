class CredentialsController < ApplicationController
  before_action :set_credential, only: [:edit, :update, :destroy]

  def index
    @credentials = Credential.order(:key)
  end

  def new
    @credential = Credential.new
  end

  def create
    @credential = Credential.new(credential_params)
    if @credential.save
      if params[:return_to] == "wizard"
        redirect_to wizard_step2_projects_path, notice: "Credential '#{@credential.key}' erstellt."
      else
        redirect_to credentials_path, notice: "Credential '#{@credential.key}' erstellt."
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @credential.update(credential_params)
      redirect_to credentials_path, notice: "Credential aktualisiert."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @credential.destroy
      redirect_to credentials_path, notice: "Credential gelöscht."
    else
      redirect_to credentials_path, alert: @credential.errors.full_messages.join(", ")
    end
  end

  private

  def set_credential
    @credential = Credential.find(params[:id])
  end

  def credential_params
    params.require(:credential).permit(:key, :value, :description)
  end
end
