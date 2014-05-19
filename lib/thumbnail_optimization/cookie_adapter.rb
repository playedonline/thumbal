require "json"

module ThumbnailOptimization
  module Persistence
    class CookieAdapter

      EXPIRES = Time.now + 31536000 # One year from now

      def initialize(context)
        @cookies = context.send(:cookies)
      end

      def [](key)
        hash[key]
      end

      def []=(key, value)
        set_cookie(hash.merge(key => value))
      end

      def delete(key)
        set_cookie(hash.tap { |h| h.delete(key) })
      end

      def keys
        hash.keys
      end

      private

      def set_cookie(value)
        @cookies[:thumbnail_optimization] = {
          :value => JSON.generate(value),
          :expires => EXPIRES
        }
      end

      def hash
        if @cookies[:thumbnail_optimization]
          begin
            JSON.parse(@cookies[:thumbnail_optimization])
          rescue JSON::ParserError
            {}
          end
        else
          {}
        end
      end

    end
  end
end
