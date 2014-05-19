
class Thumb < ActiveRecord::Base

  include Paperclip::Glue

  belongs_to :thumbnail_experiment
  attr_accessible :image, :clicks, :impressions, :thumbnail_experiment_id
  has_attached_file :image, :styles => { :medium => "300x300>", :thumb => "100x100>" }, :default_url => "/images/:style/missing.png"
  validates_attachment_content_type :image, :content_type => /\Aimage\/.*\Z/

  def self.do_something
    puts 'gg'
  end

end
