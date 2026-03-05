class Project < ApplicationRecord
  validates :name, presence: true

  has_many :project_credentials, dependent: :destroy
  has_many :credentials, through: :project_credentials
  has_many :pipelines, dependent: :destroy

  def credential_for(role)
    project_credentials.find_by(role: role)&.credential&.value
  end
end
