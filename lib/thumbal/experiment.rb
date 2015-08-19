require 'open-uri'
module Thumbal
  class Experiment
    attr_accessor :name
    attr_accessor :alternatives
    attr_accessor :max_participants
    attr_accessor :user_count

    def initialize(name, alternatives=nil, max_participants=nil)
      @name = name.to_s
      self.alternatives = alternatives
      self.max_participants = max_participants
    end

    def self.all
      Thumbal.redis.smembers(:experiments).map { |e| find(e) }
    end

    def self.find(name)
      if Thumbal.redis.smembers(:experiments).include? name
        obj = self.new(name)
        obj.load_from_redis
      else
        obj = nil
      end
      obj
    end

    def save
      validate!

      if new_record?
        Thumbal.redis.sadd(:experiments, name)
        @alternatives.reverse.each do |a|
          Thumbal.redis.lpush(name, a.name)
          a.set_unique_id self.version
          a.save
        end

        Thumbal.redis.set("%s:max_participants" % name, max_participants)
      else
        if (sync_redis)
          # If redis synced was needed reset experiment fields
          reset
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
      !Thumbal.redis.exists(name)
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
        if alternative.kind_of?(Thumbal::Alternative)
          alternative
        else
          Thumbal::Alternative.new(alternative, @name)
        end
      end
    end


    def winner
      if w = Thumbal.redis.hget(:experiment_winner, name)
        Thumbal::Alternative.new(w, name)
      else
        nil
      end
    end

    def winner=(winner_name)
      Thumbal.redis.hset(:experiment_winner, name, winner_name.to_s)
    end

    def set_winner

      self.winner = (alternatives.max_by { |a| a.ctr }).name
      set_winning_thumb(self.winner.name)

      self.winner
    end


    def set_winning_thumb(image_url)
      begin
        game = Kernel.const_get(model_name).find(name)
        if game.present?
          game.send("#{model_thumb_field}=", open(image_url))
          # file.close
          game.save!
        end

      rescue Exception => ex
        puts "Thumbal: ERROR when trying to set abtest winner for #{name}: " + ex.message
      end

    end


    def participant_count
      alternatives.inject(0) { |sum, a| sum + a.participant_count }
    end

    def user_count
      Thumbal.redis.get "#{self.key}:participants"
    end

    def increment_users
      Thumbal.redis.incrby "#{self.key}:participants",1
    end

    def reset_winner
      Thumbal.redis.hdel(:experiment_winner, name)
    end

    def start_time
      self.class.find_start_time_by_name_and_version @name, self.version
    end

    def end_time
      self.class.find_end_time_by_name_and_version @name, self.version
    end

    def self.find_start_time_by_name_and_version (name, version)
      t = Thumbal.redis.hget(:experiment_start_times, "#{name}:#{version}")

      # Backwards compatibility for existing experiments (from before adding exp. version to name)
      if (t.nil? && version.to_s == "0")
        t = Thumbal.redis.hget(:experiment_start_times, name)
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
      t = Thumbal.redis.hget(:experiment_end_times, "#{name}:#{version}")
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
      @version ||= (Thumbal.redis.get("#{name.to_s}:version").to_i || 0)
    end

    def increment_version
      @version = Thumbal.redis.incr("#{name}:version")
    end

    def key
      if version.to_i > 0
        "#{name}:#{version}"
      else
        name
      end
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
      #Thumbal.redis.del("#{self.name}:users")
      Thumbal.redis.del("#{self.name}:participants")
      #Remove experiment from active experiments set
      Thumbal.redis.srem(:experiments, name)
      #Delete Alternative list for this experiment
      Thumbal.redis.del(name)
       increment_version
    end


    def load_from_redis
      self.alternatives = load_alternatives_from_redis
      self.max_participants = Thumbal.redis.get("%s:max_participants" % self.name).to_i
    end


    def get_alternative_participants(alt_name)
      alternatives.each do |alt|
        if alt.name == alt_name
          return alt.participant_count
        end
      end
      0
    end


    def get_alternative_clicks(alt_name)
      alternatives.each do |alt|
        if alt.name == alt_name
          return alt.clicks
        end
      end
      0
    end

    def get_alternative_positive_clicks(alt_name)
      alternatives.each do |alt|
        if alt.name == alt_name
          return alt.positive_clicks
        end
      end
      0
    end

    def get_alternative_negative_clicks(alt_name)
      alternatives.each do |alt|
        if alt.name == alt_name
          return alt.negative_clicks
        end
      end
      0
    end

    def get_sorted_alternatives
      return [] if alternatives.nil?
      alternatives.sort_by {|alt| alt.ctr}.reverse
    end

    def is_maxed
      ans = true
      alternatives.each do |alt|
        ans = (ans and is_alternative_maxed(alt))
      end
      ans
    end

    protected

    # Check if redis data lines up with experiment object, and if not replace redis data. return true if sync was needed
    def sync_redis

      existing_alternatives = load_alternatives_from_redis
      sync_needed =  !(existing_alternatives == @alternatives.map(&:name))
      if sync_needed
        #Delete past alternative fields for this experiment
        existing_alternatives.map{|alt_name| Alternative.new(alt_name,@name)}.each(&:delete)
        # Delete past alternative list for this experiment
        Thumbal.redis.del(@name)
        # Add current alternatives to alternative list
        @alternatives.reverse.each do |a|
          Thumbal.redis.lpush(@name, a.name)
          a.set_unique_id self.version
        end
      end
      sync_needed
    end

    def experiment_config_key
      "experiment_configurations/#{@name}"
    end


    def load_alternatives_from_redis
      Thumbal.redis.lrange(@name, 0, -1)
    end

    def is_alternative_maxed(alternative)
      alternative.participant_count >= max_participants
    end

  end
end
