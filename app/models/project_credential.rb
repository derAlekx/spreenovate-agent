class ProjectCredential < ApplicationRecord
  belongs_to :project
  belongs_to :credential
  validates :role, presence: true, uniqueness: { scope: :project_id }
end
