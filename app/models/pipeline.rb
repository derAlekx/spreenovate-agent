class Pipeline < ApplicationRecord
  belongs_to :project
  has_many :pipeline_steps, -> { order(:position) }, dependent: :destroy
  has_many :items, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true

  before_validation :generate_slug, if: -> { slug.blank? && name.present? }

  def daily_limit
    5
  end

  def sent_today_count
    items.where(status: "sent")
         .where("json_extract(data, '$.sent_at') >= ?", Date.current.iso8601)
         .count
  end

  def remaining_sends_today
    [daily_limit - sent_today_count, 0].max
  end

  private

  def generate_slug
    self.slug = name.parameterize
  end
end
