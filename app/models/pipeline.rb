class Pipeline < ApplicationRecord
  belongs_to :project
  has_many :pipeline_steps, -> { order(:position) }, dependent: :destroy
  has_many :items, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true

  before_validation :generate_slug, if: -> { slug.blank? && name.present? }

  private

  def generate_slug
    self.slug = name.parameterize
  end
end
