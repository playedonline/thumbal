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


    # Gets all running thumbs ab tests for user as a hash {<game_id> => <alternative_name>}
    def ab_test_active_thumb_experiments

      res = {}
      active_test_names = ThumbnailExperiment.uniq.where(is_active: 1).pluck('game_id')
      active_test_names.each do |id|

        experiment = Thumbal::Experiment.find(id.to_s)
        res[id] = start_experiment( experiment )

      end

      res
    end

    def override_present?(experiment_name)
      defined?(params) && params[experiment_name]
    end

    def override_alternative(experiment_name)
      params[experiment_name] if override_present?(experiment_name)
    end

    def ab_user
      @ab_user ||= Thumbal::CookieAdapter.new(self)
    end

    def get_user_abtests_alt_ids
      # Ignore keys with ':finished'/':attempt', which mark conversions/conversion attempt, we want to only go over keys that mark participating
      # in a test
      ab_user.keys.reject { |key| key.ends_with?(':finished', ':attempt') }.map { |key| Alternative.find_alternative_unique_id(key.split(':')[0], ab_user[key]) }.join(',')
    end


    protected

    # Gets an alternative for the user- checks if the experiment is still running and if it's a new user. Otherwise get winner/value form cookie.
    # Params:
    # +experiment+:: the experiment to select an alternative from
    def start_experiment(experiment)

      if ! experiment.winner.nil?
        ret = experiment.winner.name
      else
        if ab_user[experiment.key]
          ret = ab_user[experiment.key]
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
      ab_user[experiment.key] = ret
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
