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
      thumb_exp = ThumbnailExperiment.create(game_id: game_id)  #create the experiment

      #add the images to db
      thumbs.each do |file|
        thumb = Thumb.create(image: file[:tempfile])
        thumb.save

        #link thumbs to experiment
        thumb_exp.thumbs << thumb
      end

      thumb_exp.save

      #save to Redis
      images = thumb_exp.thumbs.map{|t| t.image.to_s}
      exp = Experiment.new(game_id.to_s, images, max_participants)
      exp.save

    end


    def get_uuid(context)
      @cookies = context.send(:cookies)
      @cookies[user_id_cookie_key]
    end

    # Gets all running thumbs ab tests for user as a hash {<game_id> => <alternative_name>}
    def ab_test_active_thumb_experiments(context)

      res = {}
      active_test_names = ThumbnailExperiment.uniq.where(is_active: 1).pluck('game_id')
      active_test_names.each do |id|

        experiment = Thumbal::Experiment.find(id.to_s)
        res[id] = get_user_alternative( experiment, get_uuid(context) )

      end

      res
    end

    def override_present?(experiment_name)
      defined?(params) && params[experiment_name]
    end

    def override_alternative(experiment_name)
      params[experiment_name] if override_present?(experiment_name)
    end

    def record_thumb_click(context, game_id)
      exp = Experiment.find(game_id)
      if exp.winner.nil? #still active
        alt = get_user_alternative(exp, get_uuid(context))
        exp.alternatives.each do |a|
          if a.name == alt
            a.record_click
          end
        end
      end
    end

    protected

    # Gets an alternative for the user- checks if the experiment is still running and if it's a new user. Otherwise get winner/value form redis cache.
    # Params:
    # +experiment+:: the experiment to select an alternative from
    def get_user_alternative(experiment, uuid)

      if ! experiment.winner.nil?
        ret = experiment.winner.name
      else
        if redis.hget("#{experiment.name}:users", "#{uuid}")
          ret = redis.hget("#{experiment.name}:users","#{uuid}")
        else
          if experiment.max_participants > experiment.participant_count
            ret = experiment.choose
          else
            experiment.set_winner
            update_db(experiment, true)
            ret = experiment.winner.name
          end
        end
      end
      redis.hset("#{experiment.name}:users","#{uuid}", ret)
      ret
    end


    # Updates experiment data in the database. Usually called when reaching max_participants.
    # Params:
    # +experiment+:: the experiment to select an alternative from
    def update_db(experiment, finish=false)

      game_id = experiment.name.to_i
      test = ThumbnailExperiment.where(game_id: game_id, is_active: 1)

      test.thumbs.each do |alternative|
        alternative.impressions = experiment.get_alternative_participants(alternative.image)
        alternative.clicks = experiment.get_alternative_clicks(alternative.image)
        alternative.save
      end

      if finish
        test.is_active = 0
      end
      test.save

    end

  end
end
