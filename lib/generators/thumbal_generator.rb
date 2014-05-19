require 'rails/generators/active_record'

module Thumbal
  class ThumbnailOptimizationGenerator < ActiveRecord::Generators::Base
    desc "Create a migration to add an optimization table"

    def self.source_root
      @source_root ||= File.expand_path('../templates', __FILE__)
    end

    def generate_migration
      migration_template "thumbal_migration.rb.erb", "db/migrate/create_thumbnail_experiments"
      migration_template "paperclip_properties_migration.rb.erb", "db/migrate/create_paperclip_properties"
    end
  end
end