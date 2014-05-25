# Thumbal

A gem for creating thumbnail ab tests to optimize your thumbnails

## Installation

Add this line to your application's Gemfile:

    gem 'thumbal', :git => 'git@github.com:playedonline/thumbal.git'

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
    Thumbal.user_id_cookie_key = 'uuid'
    Thumbal.reset_app_thumbs_cache_callback = Proc.new { <some method>}
    
    * redis => the redis server that your app uses
    * model_to_s => the property used for model presentation (like name / to_s function)
    * model_name => the name of the model (used to get an instance of the model with:
         Kernel.const_get(model_name).find({id})
    * model_thumb_field => the property used for getting/setting the model's thumb (used when setting the winner)
    * user_id_cookie_key => the string key your app uses to store a unique id for the user in the browser's cookie. NOTE: without this the whole thing just won't work...
    * reset_app_thumbs_cache_callback => a Proc that you want to call in order to clear your web page cache after starting a new abtest / choosing a winner

 
to use thumbal's dashboard and add an iframe to your view:

```html
<iframe id="optimization_frame" src="/thumbal?game_id=<%= game.present? ? game.id : '' %>"></iframe>
```

  * game_id is the id of the object you want to create an experiment for (optional)


Get all live experiments:

    Thumbal::Helper.ab_test_active_thumb_experiments({a web context- i.e Controller})

the returned value is a hash. the keys are game_id, values are the url of the selected test alternative, for example:

    {93711=>"http://s3.amazonaws.com/mobile_catalog/system/static/thumbs/square/47/original_RackMultipart20140522-76792-1vpr9rj.?1400750291", 93841=>"http://s3.amazonaws.com/mobile_catalog/system/static/thumbs/square/6/original_RackMultipart20140520-70543-19d4llh.?1400593134", 93845=>"http://s3.amazonaws.com/mobile_catalog/system/static/thumbs/square/10/original_RackMultipart20140521-74112-1dxdxec.?1400663415"}
    
    
Record click event for alternative:

    Thumbal::Helper.record_thumb_click({web context}, {game_id})
    
where web context is something that responds to :cookies (i.e an ActionController::Base to get the user id cookie)


## Contributing

1. Fork it ( http://github.com/<my-github-username>/thumbal/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
