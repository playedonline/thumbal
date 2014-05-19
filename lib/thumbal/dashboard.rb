require 'sinatra/base'
require 'thumbal'

module Thumbal
  class Dashboard < Sinatra::Base

    dir = File.dirname(File.expand_path(__FILE__))

    set :views, "#{dir}/dashboard/views"
    set :public_folder, "#{dir}/dashboard/public"
    set :static, true
    set :method_override, true


    get '/' do


      @current_experiments = Experiment.all
      @finished_experiments = ThumbnailExperiment.where(is_active: 0)
      #
      # if params.present?
      #   @game = Game.find(params)
      # end

      @game_id = params['game_id']
      @game_class_name = params['game_class_name'].to_s
      @thumb_url_method = params['thumb_url_method'].to_s
      @game_name_method = params['game_name_method'].to_s

      erb :index
    end


    post '/start_test' do

      if params[:upload].blank?
        return
      end


      ThumbnailOptimization::Helper.init_experiment(params[:game_id], params[:upload], params[:max_participants])

    end

  end
end