class Credential < ApplicationRecord
  encrypts :value
  validates :key, presence: true, uniqueness: true
  validates :value, presence: true

  has_many :project_credentials, dependent: :restrict_with_error
  has_many :projects, through: :project_credentials
end
