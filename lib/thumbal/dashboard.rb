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


      cached_experiments = Experiment.all
      @current_experiments = []
      cached_experiments.each do |x|
        if x.winner.nil?
          @current_experiments << x
        end
      end
      @finished_experiments = ThumbnailExperiment.where(is_active: 0)
      if params['game_id'].present?
        @game = Kernel.const_get(model_name).find(params['game_id'])
      end

      erb :index
    end


    post '/start_test' do

      if params[:upload].blank?
        return
      end


      Thumbal::Helper.init_experiment(params[:game_id], params[:upload], params[:max_participants])
      redirect url('/')
    end

  end
end