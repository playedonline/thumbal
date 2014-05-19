module Thumbal
  class Experiment
    attr_accessor :name
    attr_accessor :alternatives
    attr_accessor :max_participants

    def initialize(name, alternatives=nil, max_participants=nil)
      @name = name.to_s
      self.alternatives = alternatives
      self.max_participants = max_participants
    end

    def self.all
      ThumbnailOptimization.redis.smembers(:experiments).map { |e| find(e) }
    end

    def self.active_experiments_names
      ThumbnailOptimization.redis.smembers(:experiments)
    end

    def self.find(name)
      if ThumbnailOptimization.redis.smembers(:experiments).include? name
        obj = self.new(name)
        obj.load_from_redis
      else
        obj = nil
      end
      obj
    end

    def self.find_or_create(label, *alternatives)

      exp = self.new label, :alternatives => alternatives
      exp.save
      exp
    end

    def save
      validate!

      if new_record?
        ThumbnailOptimization.redis.sadd(:experiments, name)
        @alternatives.reverse.each do |a|
          ThumbnailOptimization.redis.lpush(name, a.name)
          a.set_unique_id self.version
          a.save
        end

        ThumbnailOptimization.redis.set("%s:max_participants" % name, max_participants)
      else

        existing_alternatives = load_alternatives_from_redis
        unless existing_alternatives == @alternatives.map(&:name)
          reset
          @alternatives.each(&:delete)
          ThumbnailOptimization.redis.lrange(@name, 0, -1).redis.del(@name)
          @alternatives.reverse.each do |a|
            ThumbnailOptimization.redis.lrange(@name, 0, -1).redis.lpush(name, a.name)
            a.set_unique_id self.version
          end

        end
      end

      self
    end

    def validate!
      if @alternatives.empty?
        raise ExperimentNotFound.new("Experiment #{@name} not found")
      end
      @alternatives.each { |a| a.validate! }

    end

    def new_record?
      !ThumbnailOptimization.redis.exists(name)
    end

    def ==(obj)
      self.name == obj.name
    end

    def [](name)
      alternatives.find { |a| a.name == name }
    end

    def alternatives=(alts)
      if alts.nil?
        return
      end
      @alternatives = alts.map do |alternative|
        if alternative.kind_of?(ThumbnailOptimization::Alternative)
          alternative
        else
          ThumbnailOptimization::Alternative.new(alternative, @name)
        end
      end
    end

    def choose
      alt = alternatives.sample
      alt.name
    end

    def event_types
      event_names = []
      alternatives = @alternatives.each do |alternative|
        event_names = event_names + alternative.events_hash.keys
      end
      event_names.uniq
    end

    def event_totals
      totals_hash = {}
      @alternatives.each do |alternative|
        alternative.events_hash.each do |event_name, amount|
          totals_hash[event_name] = totals_hash[event_name].present? ? (totals_hash[event_name].to_i+amount.to_i) : amount.to_i
        end

      end
      totals_hash
    end


    def winner
      if w = ThumbnailOptimization.redis.hget(:experiment_winner, name)
        ThumbnailOptimization::Alternative.new(w, name)
      else
        nil
      end
    end

    def winner=(winner_name)
      ThumbnailOptimization.redis.hset(:experiment_winner, name, winner_name.to_s)
    end

    def set_winner

      winner = (alternatives.max_by {|a| a.ctr}).name
      winner
    end

    def participant_count
      alternatives.inject(0) { |sum, a| sum + a.participant_count }
    end

    def control
      alternatives.first
    end

    def reset_winner
      ThumbnailOptimization.redis.hdel(:experiment_winner, name)
    end

    def start_time
      self.class.find_start_time_by_name_and_version @name, self.version
    end

    def end_time
      self.class.find_end_time_by_name_and_version @name, self.version
    end

    def self.find_start_time_by_name_and_version (name, version)
      t = ThumbnailOptimization.redis.hget(:experiment_start_times, "#{name}:#{version}")

      # Backwards compatibility for existing experiments (from before adding exp. version to name)
      if (t.nil? && version.to_s == "0")
        t = ThumbnailOptimization.redis.hget(:experiment_start_times, name)
      end

      if t
        # Check if stored time is an integer
        if t =~ /^[-+]?[0-9]+$/
          t = Time.at(t.to_i)
        else
          t = Time.parse(t)
        end
      end
    end

    def self.find_end_time_by_name_and_version (name, version)
      t = ThumbnailOptimization.redis.hget(:experiment_end_times, "#{name}:#{version}")
      if t
        # Check if stored time is an integer
        if t =~ /^[-+]?[0-9]+$/
          t = Time.at(t.to_i)
        else
          t = Time.parse(t)
        end
      end
    end

    def next_alternative
      winner || random_alternative
    end

    def random_alternative
      if alternatives.length > 1
        algorithm.choose_alternative(self)
      else
        alternatives.first
      end
    end

    def version
      @version ||= (ThumbnailOptimization.redis.get("#{name.to_s}:version").to_i || 0)
    end

    def increment_version
      @version = ThumbnailOptimization.redis.incr("#{name}:version")
    end

    def key
      if version.to_i > 0
        "#{name}:#{version}"
      else
        name
      end
    end

    def goals_key
      "#{name}:goals"
    end

    def finished_key
      "#{key}:finished"
    end

    def attempt_key
      "#{key}:attempt"
    end

    def reset
      alternatives.each(&:reset)
      reset_winner
      increment_version
      alternatives.each { |alt| alt.set_unique_id(version) }
    end

    def delete
      alternatives.each(&:delete)
      reset_winner
      ThumbnailOptimization.redis.srem(:experiments, name)
      ThumbnailOptimization.redis.del(name)
      increment_version
    end

    def load_from_redis
      self.alternatives = load_alternatives_from_redis
      self.max_participants = ThumbnailOptimization.redis.get("%s:max_participants" % self.name).to_i
    end


    def get_alternative_participants(alt_name)
      alternatives.each do |alt|
        if alt.name == alt_name
          return alt.participant_count
        end
      end
    end


    def get_alternative_clicks(alt_name)
      alternatives.each do |alt|
        if alt.name == alt_name
          return alt.clicks
        end
      end
    end

    protected

    def experiment_config_key
      "experiment_configurations/#{@name}"
    end

    def load_goals_from_configuration
      goals = ThumbnailOptimization.configuration.experiment_for(@name)[:goals]
      if goals.nil?
        goals = []
      else
        goals.flatten
      end
    end

    def load_alternatives_from_configuration
      alts = ThumbnailOptimization.configuration.experiment_for(@name)[:alternatives]
      raise ArgumentError, "Experiment configuration is missing :alternatives array" unless alts
      if alts.is_a?(Hash)
        alts.keys
      else
        alts.flatten
      end
    end

    def load_alternatives_from_redis
      ThumbnailOptimization.redis.lrange(@name, 0, -1)

    end

  end
end
