class ThumbnailExperiment < ActiveRecord::Base

  has_many :thumbs, :dependent => :destroy
  accepts_nested_attributes_for :thumbs, allow_destroy: true

  attr_accessible :thumbs, :is_active, :game_id

  def get_sorted_alternatives
    thumbs.sort_by { |alt| (alt.clicks.present? and alt.impressions.present? and alt.impressions != 0) ? alt.clicks.to_f/alt.impressions : 0 }.reverse
  end
end
