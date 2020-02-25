# PgqPrometheus

Highly configurable Prometheus metrics for PGQ postgres extension

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'pgq_prometheus'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install pgq_prometheus

## Usage

Basic usage with rails

### config/initializers/pgq_prometheus.rb
```ruby
require 'pgq_prometheus'

# If you use postgresql library/orm other then active_record
# look at PgqPrometheus::SqlCaller::ActiveRecord for example of what sql caller should return.
require 'pgq_prometheus/sql_caller/active_record'

# We will configure processor here
PgqPrometheus::Processor.tap do |processor|
  # you must set sql_caller to retrieve data from postgres
  processor.sql_caller = PgqPrometheus::SqlCaller::ActiveRecord.new(ApplicationRecord)
  # you can setup processor logger
  processor.logger = Rails.logger
  # you can do something custom when processor rescues and exception
  processor.on_error = proc { |e| ErrorMailer.notify(e).deliver_later }
end

# we keep configuration is separate file because both processor and collector should require it.
require 'pgq_prometheus_configure' # @see lib/pgq_prometheus_configure.rb

# Will start thread which will collect pgq metrics every 30 seconds.
PgqPrometheus::Processor.start(frequency: 30)
```

### lib/pgq_prometheus_configure.rb
```ruby
# We will keep metrics configuration here
 
PgqPrometheus.configure do |config|
  # these are default metrics - no need to define them manually
  config.register_gauge :new_events, 'new events qty for queue',
    from: :queue, column: :ev_new

  config.register_gauge :events_per_second, 'new events qty for queue',
    from: :queue, column: :ev_per_sec

  config.register_gauge :pending_events, 'pending events qty for queue and consumer',
                     from: :consumer 

  # you can define custom metrics
  config.register_histogram :new_events_hist, 'PGQ new events histogram',
    from: :queue,
    labels: { custom_label_name: 'qwe' },
    buckets: [1_000, 100, 50, 10, 1, 0]
  config.register_counter :custom_queue_metric, 'something custom for queue',
    from: :queue, 
    apply: proc { |queue_info| CustomQueueMetric.call queue_info[:queue_name] }
  config.register_counter :custom_consumer_metric, 'something custom',
    from: :queue,
    apply: proc { |consumer_info, queue_info| CustomConsumerMetric.call(queue_info, consumer_info) }

  # and remove metrics (event default ones)
  config.unregister_metric :new_events_hist

  # and override type
  config.type = 'postresql_queue'
end
```

### lib/prometheus_collectors.rb
```ruby
# Require all custom prometheus collectors here
 
require 'pgq_prometheus/collector' 
require_relative 'pgq_prometheus_configure' 
```

    $ bundle exec prometheus_exporter -a /path/to/mypoject/lib/prometheus_collectors.rb
    $ rails s

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/senid231/pgq_prometheus. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/senid231/pgq_prometheus/blob/master/CODE_OF_CONDUCT.md).


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the PgqPrometheus project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/senid231/pgq_prometheus/blob/master/CODE_OF_CONDUCT.md).
