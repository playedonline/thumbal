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


      Thumbal::Helper.init_experiment(params[:game_id], params[:upload], params[:max_participants], params[:include_current])
      redirect url('/')
    end

    post '/delete_test' do

      if params['exp_id'].present?
        exp = ThumbnailExperiment.find(params['exp_id'])
        exp.delete

      end

      redirect url('/')
    end

    post '/choose_alternative' do

      exp_name = params['exp_name']
      alt_name = params['alt_name']

      if exp_name.present? and alt_name.present?
        experiment = Experiment.find(exp_name)
        experiment.winner=alt_name
        experiment.set_winning_thumb(alt_name)
        Thumbal::Helper.update_db(experiment, true)
        experiment.delete
        begin
          Thumbal::Helper.call_reset_cache_hook
        end
      end


      redirect url('/')

    end

  end
end