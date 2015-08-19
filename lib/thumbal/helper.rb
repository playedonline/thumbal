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
              thumb.impressions = exp.get_alternative_participants(thumb.image(:thumb).to_s)
              thumb.clicks = exp.get_alternative_clicks(thumb.image(:thumb).to_s)
              thumb.positive_clicks = exp.get_alternative_positive_clicks(thumb.image(:thumb).to_s)
              thumb.negative_clicks = exp.get_alternative_negative_clicks(thumb.image(:thumb).to_s)
              thumb.save!
            end
          end

          #deactivate running test and remove form redis
          test.is_active = 0
          test.save


        end
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
      if user_id_signed
        @cookies.signed[user_id_cookie_key]
      else
        @cookies[user_id_cookie_key]
      end
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
            res[id] = get_user_alternative(context,experiment, get_uuid(context),false)
          end
        end
      end
      res
    end


    def enter_user_to_experiment(context, experiment_name)
      res = {}
      browser = Browser.new(:ua => context.request.env['HTTP_USER_AGENT'])
      if !browser.bot?
        active_tests_for_name = ThumbnailExperiment.where({game_id: experiment_name, is_active: 1})
        if active_tests_for_name.present?
          experiment = Thumbal::Experiment.find(experiment_name.to_s)
          if experiment.present?
            res[experiment_name.to_s] = get_user_alternative(context,experiment, get_uuid(context))
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
      exp = Experiment.find(game_id.to_s)
      puts "exp:#{exp}"
      if exp.present? and exp.winner.nil? #still active
        alt = get_user_alternative(context,exp, get_uuid(context), false)
        puts "alt:#{alt}"
        exp.alternatives.each do |a|
          if a.name == alt
            puts "record click #{alt}"
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
        alt = get_user_alternative(context, exp, get_uuid(context), false)
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

    def record_play_time_click_result_by_alternative_index(alternative_index, game_id, game_play_time, critical_play_time=20)
      exp = Experiment.find(game_id)
      if exp.present? and exp.winner.nil? #still active
        if game_play_time >= critical_play_time
          exp.alternatives[alternative_index.to_i].record_positive_click
        else
          exp.alternatives[alternative_index.to_i].record_negative_click
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
        test.thumbs.each do |thumb|
          alt_name = thumb.image(:thumb).to_s
          thumb.impressions = experiment.get_alternative_participants(alt_name)
          thumb.clicks = experiment.get_alternative_clicks(alt_name)
          thumb.positive_clicks = experiment.get_alternative_positive_clicks(alt_name)
          thumb.negative_clicks = experiment.get_alternative_negative_clicks(alt_name)
          thumb.save
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

      get_user_alternative(context,exp, uuid, false)

    end

    def get_alternative_id_for_user_by_model_id(model_id,context)
      exp = Experiment.find(model_id.to_s)
      return nil if exp.nil?

      get_user_alternative_id(context,exp)
    end

    def get_experiment_version(model_id)
      experiment = Experiment.find(model_id.to_s)
      return nil if experiment.nil?

      return experiment.version
    end


    protected

    def get_user_alternative_id(context,experiment)
      exp_cookie_name = "thumbal_#{experiment.name}_#{experiment.version}"
      cookies = context.send(:cookies)
      cookies.signed[exp_cookie_name]
    end

    # Gets an alternative for the user- checks if the experiment is still running and if it's a new user. Otherwise get winner/value form redis cache.
    # Params:
    # +experiment+:: the experiment to select an alternative from
    def get_user_alternative(context,experiment, uuid, increase_impression=true)
      exp_cookie_name = "thumbal_#{experiment.name}_#{experiment.version}"
      cookies = context.send(:cookies)

      if !experiment.winner.nil?
        ret = experiment.winner.name
        cookies[exp_cookie_name].delete
      else
          if experiment.is_maxed
            finish_experiment(experiment)
            ret = experiment.winner.name
          else

            # if user was previously enrolled, get his assigned alternative from the cookie
            if  cookies[exp_cookie_name].present?
              alt_index = cookies.signed[exp_cookie_name].to_i
              ret = experiment.alternatives[alt_index].name
            # If an actual impression is being made and user wasn't previously enrolled, enroll the user, increment user count and return the user assigned alternative
            elsif increase_impression
              curr_count = experiment.increment_users.to_i
              #puts "curr_count:#{curr_count}"
              alt_index = curr_count % experiment.alternatives.length
              #puts "alt_index:#{alt_index}"
              cookies.signed[exp_cookie_name] = { :value => alt_index, :expires => 3.weeks.from_now }
              #puts "exp_cookie_name:#{exp_cookie_name}"
              ret = experiment.alternatives[alt_index].name
              #puts "experiment:#{experiment}"
              #puts "ret:#{ret}"
            end
            if increase_impression
              experiment.alternatives[alt_index].increment_participation
            end
          end
      end
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
