class ThumbnailExperiment < ActiveRecord::Base

  has_many :thumbs, :dependent => :destroy
  accepts_nested_attributes_for :thumbs, allow_destroy: true

  attr_accessible :thumbs, :is_active, :game_id

  def get_sorted_alternatives
    calc_by_total_clicks = true
    if Thumbal.calc_score_by_play_time
      thumbs.each do |t|
        if t.positive_clicks != 0 or t.negative_clicks != 0
          calc_by_total_clicks = false
        end
      end
    end

    if calc_by_total_clicks
      thumbs.sort_by { |alt| (alt.clicks.present? and alt.impressions.present? and alt.impressions != 0) ? alt.clicks.to_f/alt.impressions : 0 }.reverse
    else
      thumbs.sort_by { |alt| (alt.impressions.present? and alt.impressions != 0) ? (alt.positive_clicks + alt.negative_clicks).to_f/alt.impressions : 0 }.reverse
    end

  end
end
