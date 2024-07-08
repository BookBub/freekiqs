# Freekiqs

Sidekiq middleware that allows capturing exceptions thrown
by failed jobs and wrapping them with a `FreekiqException` exception class
that can be filtered by monitoring tools such as New Relic and
Rollbar.

#### Implementation Details

This relies on Sidekiq's built-in retry handling. Specifically, its
`retry_count` value. When a job first fails, its `retry_count` value
is nil (because it hasn't actually been retried yet). That exception,
along with subsequent exceptions from retries, are caught and wrapped
with the `FreekiqException` exception.
Cases where Freekiqs does NOT wrap the exception:
 - The `retry` option is false
 - The `freekiqs` option is not set on the worker nor globally
 - The `freekiqs` option is not set on worker and set to `false` globally
 - The `freekiqs` option is set to `false` on the worker
 - The job threw an exception that is not a StandardError (nor a subclass)
 - The number of thrown exceptions is more than specified freekiqs

Configuration example (in config/initializers/sidekiq.rb):
``` ruby
  Sidekiq.configure_server do |config|
    config.server_middleware do |chain|
      chain.add Sidekiq::Middleware::Server::Freekiqs
    end
  end
```

Worker example:
``` ruby
  class MyWorker
    include Sidekiq::Worker
    sidekiq_options freekiqs: 3

    def perform(param)
      ...
    end
  end
```

Freekiqs is disabled by default. It can be enabled per-worker
by setting `:freekiqs` on `sidekiq_options`. Or, it can be
enabled globally by adding `:freekiqs` to the middleware
registration.

Example:
``` ruby
  Sidekiq.configure_server do |config|
    config.server_middleware do |chain|
      chain.add Sidekiq::Middleware::Server::Freekiqs, freekiqs: 3
    end
  end
```

A callback can be fired when a freekiq happens.
This can be useful for tracking or logging freekiqs separately from the sidekiq logs.

Example:
``` ruby
  Sidekiq.configure_server do |config|
    config.server_middleware do |chain|
      chain.add Sidekiq::Middleware::Server::Freekiqs, callback: ->(worker, msg, queue) do
        Librato::Metrics.submit freekiqs: { value: 1, source: worker.class.name }
      end
    end
  end
```

Or callback can be set outside middleware configuration:
``` ruby
  Sidekiq::Middleware::Server::Freekiqs::callback = ->(worker, msg, queue) do
    Librato::Metrics.submit freekiqs: { value: 1, source: worker.class.name }
  end
```

An array of specific errors to be freekiq'd can be defined in the `freekiq_for` option.

Example:
``` ruby
  class MyWorker
    include Sidekiq::Worker
    sidekiq_options freekiqs: 1, freekiq_for: ['MyError']

    def perform(param)
      ...
    end
  end
```
In this case, if MyWorker fails with a MyError it will get 1 freekiq.
All other errors thrown by this worker will get no freekiqs.


If a `freekiq_for` contains a class name as a constant, any exception of that class
type *or a subclass* of that class will get freekiq'd.

Example:
``` ruby
  class SubMyError < MyError; end

  class MyWorker
    include Sidekiq::Worker
    sidekiq_options freekiqs: 1, freekiq_for: [MyError]

    def perform(param)
      ...
    end
  end
```
If MyWorker throws a SubMyError or MyError, it will get freekiq'd.

## Sidekiq Versions

Version 5 of this gem only works with Sidekiq 5 and higher. If you are using
an older version of Sidekiq, you'll need to use version [4.1.0](https://github.com/BookBub/freekiqs/tree/v4.1.0).

Version 6.5.0 of this gem works with Sidekiq 6.5 and higher. Last tested with Sidekiq 7.3.0.
