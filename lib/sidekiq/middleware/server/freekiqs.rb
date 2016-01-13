require 'sidekiq'
require 'sidekiq/util'

module Sidekiq
  class FreekiqException < RuntimeError; end

  module Middleware
    module Server
      class Freekiqs
        include Sidekiq::Util

        def initialize(opts={})
          @default_freekiqs = opts[:freekiqs]
        end

        def call(worker, msg, queue)
          yield
        rescue => ex
          freekiqs = get_freekiqs_if_enabled(worker, msg)
          if freekiqs
            if msg['retry_count'].nil? || msg['retry_count'] < freekiqs-1
              raise FreekiqException, ex.message
            else
              Sidekiq.logger.info { "Out of free kiqs for #{msg['class']} job #{msg['jid']}" }
            end
          end
          raise ex
        end

        def get_freekiqs_if_enabled(worker, msg)
          freekiqs = nil
          if msg['retry']
            if worker.class.sidekiq_options['freekiqs'] != false
              if worker.class.sidekiq_options['freekiqs']
                freekiqs = worker.class.sidekiq_options['freekiqs'].to_i
              elsif @default_freekiqs
                freekiqs = @default_freekiqs.to_i
              end
            end
          end
          freekiqs
        end
      end
    end
  end
end
