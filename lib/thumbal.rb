require 'rubygems'
require 'paperclip'
%w[alternative experiment helper version configuration thumbnail_experiment thumb dashboard].each do |f|
  require "thumbal/#{f}"
end

require 'redis/namespace'

module Thumbal

  extend self

  def redis=(server)
    @redis = Redis::Namespace.new(:thumbal, :redis => server)
  end


# Returns the current Redis connection. If none has been created, will
# create a new one.
  def redis
    return @redis
  end


  def model_name=(name_str)
    @model_name = name_str
  end

  def model_name
    return @model_name if @model_name
    self.model_name = 'Game'
    self.model_name
  end

  def model_thumb_field=(property_name)
    @model_thumb_field = property_name
  end


  def model_thumb_field
    return @model_thumb_field if @model_thumb_field
    self.model_thumb_field = 'thumb'
    self.model_thumb_field
  end

  def model_to_s=(to_s_property)
    @model_to_s = to_s_property
  end

  def model_to_s
    return @model_to_s if @model_to_s
    self.model_to_s = 'name'
    self.model_to_s
  end

  def user_id_cookie_key=(key)
    @user_id_cookie_key = key
  end

  def user_id_cookie_key
    return @user_id_cookie_key if @user_id_cookie_key
    self.user_id_cookie_key = 'uuid'
    self.user_id_cookie_key
  end

  def user_id_signed=(is_signed)
    @user_id_signed = is_signed
  end

  def user_id_signed
    @user_id_signed || false
  end

  # Call this method to modify defaults in your initializers.
  def configure
    self.configuration ||= Configuration.new
    yield(configuration)
  end

  def reset_app_thumbs_cache_callback
    return @reset_app_thumbs_cache if @reset_app_thumbs_cache
    nil
  end

  def reset_app_thumbs_cache_callback=(callback)
    @reset_app_thumbs_cache = callback
  end

  def calc_score_by_play_time
    return @calc_score_by_play_time if @calc_score_by_play_time
    nil
  end

  def calc_score_by_play_time=(value)
    @calc_score_by_play_time = value
  end
end
