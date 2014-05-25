
class Thumb < ActiveRecord::Base

  include Paperclip::Glue

  belongs_to :thumbnail_experiment
  attr_accessible :image, :clicks, :impressions, :thumbnail_experiment_id
  has_attached_file :image, :styles => { :medium => "250x250>", :thumb => "100x100>" }, :default_url => "/images/:style/missing.png", :path => "/system/static/thumbs/abtest/:id/:style_:basename.:extension"
  validates_attachment_content_type :image, :content_type => /\Aimage\/.*\Z/


end
