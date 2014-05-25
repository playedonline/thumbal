module Thumbal
  module Helper

    extend self

    # Initialize a new experiment in redis and database
    # @param game_id : the id of the object of the experiment
    # @param thumbs : an array of thumb urls (strings)
    # @param max_participants : the experiment will stop after reaching max_paeticipants
    def self.init_experiment(game_id, thumbs, max_participants=30000)

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

      thumb_exp.save

      #save to Redis
      images = thumb_exp.thumbs.map { |t| t.image.to_s }
      exp = Experiment.new(game_id.to_s, images, max_participants)
      exp.save

      call_reset_cache_hook
    end


    #Gets the user's unique id from the cookie
    def get_uuid(context)
      @cookies = context.send(:cookies)
      @cookies[user_id_cookie_key]
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
        alt = get_user_alternative(exp, get_uuid(context))
        exp.alternatives.each do |a|
          if a.name == alt
            a.record_click
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
          alternative.impressions = experiment.get_alternative_participants(alternative.image.to_s)
          alternative.clicks = experiment.get_alternative_clicks(alternative.image.to_s)
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

      get_user_alternative(exp, uuid)

    end


    protected

    # Gets an alternative for the user- checks if the experiment is still running and if it's a new user. Otherwise get winner/value form redis cache.
    # Params:
    # +experiment+:: the experiment to select an alternative from
    def get_user_alternative(experiment, uuid)

      if !experiment.winner.nil?
        ret = experiment.winner.name
      else
        if redis.hget("#{experiment.name}:users", "#{uuid}")
          ret = redis.hget("#{experiment.name}:users", "#{uuid}")
        else
          if experiment.max_participants > experiment.participant_count
            ret = experiment.choose
          else
            experiment.set_winner
            update_db(experiment, true)
            begin
              call_reset_cache_hook
            end
            ret = experiment.winner.name
          end
        end
      end
      redis.hset("#{experiment.name}:users", "#{uuid}", ret)
      ret
    end


  end
end
