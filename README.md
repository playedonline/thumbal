# Thumbal

A gem for creating thumbnail ab tests to optimize your thumbnails

## Installation

Add this line to your application's Gemfile:

    gem 'thumbal'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install thumbal

## Usage

rails g thumbal thumb
rake db:migrate

To use thumbal's dashboard:
<iframe id="optimization_frame" src="/thumbal?game_id=<%= game.present? ? game.id : '' %>&game_class_name=Game&thumb_url_method=thumb_url_small&game_name_method=name"></iframe>

*game_id is the id of the object you're testing thumbs for
*game_class_name is the name of the object's class
*thumb_url_method  (string) is the attr_accessor that gets the object's current/default thumb (optional, for displaying in the dashboard)
*game_name_method (string) is the attr_accessor that gets the object's display name (optional, for displaying in the dashboard)

## Contributing

1. Fork it ( http://github.com/<my-github-username>/thumbal/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
