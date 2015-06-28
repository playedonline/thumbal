module Thumbal
  module Helper

    extend self

    # Initialize a new experiment in redis and database
    # @param game_id : the id of the object of the experiment
    # @param thumbs : an array of thumb urls (strings)
    # @param max_participants : the experiment will stop after reaching max_paeticipants
    def self.init_experiment(game_id, thumbs, max_participants=30000, include_current=false)

      active_test = ThumbnailExperiment.where(game_id: game_id, is_active: 1)
      exp = Experiment.find(game_id.to_s)


      if active_test.present?
        active_test.each do |test|

          if exp.present?

            test.thumbs.each do |thumb|
              #store experiment results
              thumb.impressions = exp.get_alternative_participants(thumb.image.to_s)
              thumb.clicks = exp.get_alternative_clicks(thumb.image.to_s)
              thumb.save
            end
          end

          #deactivate running test and remove form redis
          test.is_active = 0
          test.save


        end
      end

      if exp.present?
        exp.delete
      end


      #start a new test for the game
      thumb_exp = ThumbnailExperiment.create(game_id: game_id) #create the experiment

      #add the images to db
      thumbs.each do |file|
        thumb = Thumb.create(image: file[:tempfile])
        thumb.save

        #link thumbs to experiment
        thumb_exp.thumbs << thumb
      end

      if include_current and model_thumb_field.present?
        current_thumb = Kernel.const_get(model_name).find(game_id).send(model_thumb_field)
        if current_thumb.present?

          experiment_thumb = Thumb.create(:image => open(URI.parse(current_thumb.to_s)) )
          # experiment_thumb = Thumb.create(image: current_thumb)
          experiment_thumb.save
          thumb_exp.thumbs << experiment_thumb
        end
      end

      thumb_exp.save

      #save to Redis
      images = thumb_exp.thumbs.map { |t| t.image(:thumb).to_s }
      exp = Experiment.new(game_id.to_s, images, max_participants)
      exp.save

      call_reset_cache_hook
    end


    #Gets the user's unique id from the cookie
    def get_uuid(context)
      @cookies = context.send(:cookies)
      @cookies[user_id_cookie_key]
    end

    def get_active_thumb_experiments_names(context)
      ThumbnailExperiment.uniq.where(is_active: 1).pluck('game_id')
    end

    # Gets all running thumbs ab tests for user as a hash {<game_id> => <alternative_name>}
    def ab_test_active_thumb_experiments(context)

      res = {}
      browser = Browser.new(:ua => context.request.env['HTTP_USER_AGENT'])
      if !browser.bot?
        active_test_names = ThumbnailExperiment.uniq.where(is_active: 1).pluck('game_id')
        active_test_names.each do |id|

          experiment = Thumbal::Experiment.find(id.to_s)
          if experiment.present?
            res[id] = get_user_alternative(experiment, get_uuid(context))
          end


        end
      end
      res
    end

    # Records a 'click' event for the user's selected alternative
    # Params:
    # +context+:: a web context that responds to :cookies (for example- a Controller (ActionController::Base))
    # +game_id+:: the id of the model object that was clicked
    def record_thumb_click(context, game_id)
      exp = Experiment.find(game_id)
      if exp.present? and exp.winner.nil? #still active
        alt = get_user_alternative(exp, get_uuid(context), false)
        exp.alternatives.each do |a|
          if a.name == alt
            a.record_click
          end
        end
      end
    end



    # Records a 'positive_click'/'negative_click event for the user's selected alternative, depending on play_time in seconds
    # Params:
    # +context+:: a web context that responds to :cookies (for example- a Controller (ActionController::Base))
    # +game_id+:: the id of the model object that was clicked
    # +game_play_time+:: the actual play time of the game that was clicked
    # +critical_play_time+:: the number of seconds that determine if the click was good or bad
    def record_play_time_click_result(context, game_id, game_play_time, critical_play_time=20)

      exp = Experiment.find(game_id)
      if exp.present? and exp.winner.nil? #still active
        alt = get_user_alternative(exp, get_uuid(context), false)
        exp.alternatives.each do |a|
          if a.name == alt
            if game_play_time >= critical_play_time
              a.record_positive_click
            else
              a.record_negative_click
            end
          end
        end
      end

    end


    # Updates experiment data in the database. Usually called when reaching max_participants.
    # Params:
    # +experiment+:: the experiment to select an alternative from
    def update_db(experiment, finish=false)

      game_id = experiment.name.to_i
      active_tests = ThumbnailExperiment.where(game_id: game_id, is_active: 1)

      active_tests.each do |test|
        test.thumbs.each do |alternative|
          alt_name = alternative.image(:thumb).to_s
          alternative.impressions = experiment.get_alternative_participants(alt_name)
          alternative.clicks = experiment.get_alternative_clicks(alt_name)
          alternative.positive_clicks = experiment.get_alternative_positive_clicks(alt_name)
          alternative.negative_clicks = experiment.get_alternative_negative_clicks(alt_name)
          alternative.save
        end

        if finish
          test.is_active = 0
        end
        test.save
      end

    end

    def call_reset_cache_hook
      Thumbal.reset_app_thumbs_cache_callback.call if Thumbal.reset_app_thumbs_cache_callback
    end


    def get_alternative_for_user_by_model_id(model_id, context)
      uuid = get_uuid(context)
      return nil if uuid.nil?

      exp = Experiment.find(model_id.to_s)
      return nil if exp.nil?

      get_user_alternative(exp, uuid, false)

    end

    def get_experiment_version(model_id)
      experiment = Experiment.find(model_id.to_s)
      return nil if experiment.nil?

      return experiment.version
    end


    protected

    # Gets an alternative for the user- checks if the experiment is still running and if it's a new user. Otherwise get winner/value form redis cache.
    # Params:
    # +experiment+:: the experiment to select an alternative from
    def get_user_alternative(experiment, uuid, increase_impression=true)

      if !experiment.winner.nil?
        ret = experiment.winner.name
      else
        if Thumbal.redis.hget("#{experiment.name}:users", "#{uuid}")
          ret = Thumbal.redis.hget("#{experiment.name}:users", "#{uuid}")
          if increase_impression
            experiment[ret].increment_participation
          end

          if experiment.is_maxed
            finish_experiment(experiment)
          end

        else
          if experiment.is_maxed
            finish_experiment(experiment)
            ret = experiment.winner.name
          else
            ret = experiment.choose(increase_impression)
          end
        end
      end
      Thumbal.redis.hset("#{experiment.name}:users", "#{uuid}", ret)
      ret
    end

    def finish_experiment(experiment)
      experiment.set_winner
      update_db(experiment, true)
      begin
        call_reset_cache_hook
      end
    end
  end
end
