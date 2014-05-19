module Thumbal
  class Alternative
    attr_accessor :name
    attr_accessor :experiment_name

    def initialize(name, experiment_name)
      @experiment_name = experiment_name
      if Hash === name
        @name = name[:name]
      else
        @name = name
        @weight = 1
      end
    end

    def self.get_all_historical_alternatives
      Thumbal.redis.lrange('all_alternative_ids', 0, -1).map do |alt_id|
        alt_info = Thumbal.redis.hmget "alternative_#{alt_id}_info", 'abtest_name', 'abtest_version', 'alternative_name', 'channel'
        {:alt_id => alt_id, :abtest_name => alt_info[0], :abtest_version => alt_info[1], :alternative_name => alt_info[2], :channel => alt_info[3] }
      end
    end

    def set_unique_id experiment_version
      if Thumbal.redis.hsetnx key, 'unique_id', -1
        next_id = Thumbal.redis.incrby 'alternative_next_id', 1
        Thumbal.redis.hset key, 'unique_id', next_id

        # Will be used to fetch all historical data
        Thumbal.redis.lpush 'all_alternative_ids', next_id
        Thumbal.redis.hmset "alternative_#{next_id}_info", 'abtest_name', experiment_name, 'abtest_version', experiment_version, 'alternative_name', name
      end
    end

    def self.find_alternative_unique_id experiment_name, alternative_name
      alternative_key = build_key experiment_name, alternative_name
      id = Thumbal.redis.hget alternative_key, 'unique_id'

      # Just in case set_unique_id (which is not atomic and doesn't use locks is just in the middle of execution)
      if id.to_s == "-1"
        sleep 0.2.seconds
        id = Thumbal.redis.hget alternative_key, 'unique_id'
      end

      id
    end

    def to_s
      name
    end

    def participant_count
      Thumbal.redis.hget(key, 'participant_count').to_i
    end

    def participant_count=(count)
      Thumbal.redis.hset(key, 'participant_count', count.to_i)
    end

    def record_click
      Thumbal.redis.incrby(key+":click", 1)
    end

    def clicks
      Thumbal.redis.get(key+":click").to_i
    end

    def increment_participation
      Thumbal.redis.hincrby key, 'participant_count', 1
    end

    def control?
      experiment.control.name == self.name
    end

    def experiment
      Thumbal::Experiment.find(experiment_name)
    end


    def ctr

      return 0 if participant_count.to_f == 0

      clicks = Thumbal.redis.get(key+":click").to_f
      impressions = participant_count.to_f

      clicks/impressions

    end

    def save
      Thumbal.redis.hsetnx key, 'participant_count', 0
      Thumbal.redis.setnx key+':click', 0

    end

    def validate!
      unless String === @name
        raise ArgumentError, 'Alternative must be a string'
      end
    end

    def reset
      Thumbal.redis.hmset key, 'participant_count', 0, key+':click', 0
    end

    def delete
      Thumbal.redis.del(key)
      Thumbal.redis.del(key+":click")
    end

    private

    def key
      self.class.build_key experiment_name, name
    end

    def self.build_key(experiment_name, alternative_name)
      "#{experiment_name}:#{alternative_name}"
    end

  end
end
