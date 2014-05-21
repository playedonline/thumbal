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

To use thumbal, create a thumbal initializer (in config/initializers):

    Thumbal.redis = $redis
    Thumbal.model_to_s = 'name'
    Thumbal.model_name = 'Game'
    Thumbal.model_thumb_field = 'thumb'
 
to use thumbal's dashboard and add an iframe to your view:

```html
<iframe id="optimization_frame" src="/thumbal?game_id=<%= game.present? ? game.id : '' %>"></iframe>
```

  * game_id is the id of the object you want to create an experiment for (optional)

## Contributing

1. Fork it ( http://github.com/<my-github-username>/thumbal/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
