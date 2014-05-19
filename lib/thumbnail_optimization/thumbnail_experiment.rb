class ThumbnailExperiment < ActiveRecord::Base

  has_many :thumbs, :dependent => :destroy
  accepts_nested_attributes_for :thumbs, allow_destroy: true

  attr_accessible :thumbs, :is_active, :game_id

  def self.do_something
    puts 'gg'
  end

end
