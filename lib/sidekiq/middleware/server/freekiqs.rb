require 'sidekiq'
require 'sidekiq/util'

module Sidekiq
  class FreekiqException < RuntimeError; end

  module Middleware
    module Server
      class Freekiqs
        include Sidekiq::Util
        @@callback = nil

        def initialize(opts={})
          @default_freekiqs = opts[:freekiqs]
          @default_freekiq_for = opts[:freekiq_for]
          @@callback = opts[:callback]
        end

        def call(worker, msg, queue)
          yield
        rescue => ex
          freekiqs = get_freekiqs_if_enabled(worker, ex)
          if freekiqs
            if msg['retry_count'].nil? || msg['retry_count'] < freekiqs-1
              begin
                @@callback.call(worker, msg, queue) if @@callback
              rescue => callback_exception
                Sidekiq.logger.info { "Freekiq callback failed for #{msg['class']} job #{msg['jid']}" }
              ensure
                raise FreekiqException, ex.message
              end
            else
              Sidekiq.logger.info { "Out of freekiqs for #{msg['class']} job #{msg['jid']}" }
            end
          end
          raise ex
        end

        def get_freekiqs_if_enabled(worker, ex)
          freekiqs = nil
          if worker.class.get_sidekiq_options['retry']
            if worker.class.get_sidekiq_options['freekiqs'] != false
              errors = get_freekiq_errors(worker)
              if worker.class.get_sidekiq_options['freekiqs']
                freekiqs = get_freekiqs(worker.class.get_sidekiq_options['freekiqs'], ex, errors)
              elsif @default_freekiqs
                freekiqs = get_freekiqs(@default_freekiqs, ex, errors)
              end
            end
          end
          freekiqs
        end

        def get_freekiq_errors(worker)
          if worker.class.get_sidekiq_options['freekiq_for']
            worker.class.get_sidekiq_options['freekiq_for']
          elsif @default_freekiq_for
            @default_freekiq_for
          end
        end

        def get_freekiqs(freekiqs, ex, errors)
          if errors
            if error_whitelisted?(ex, errors)
              freekiqs.to_i
            end
          else
            freekiqs.to_i
          end
        end

        def error_whitelisted?(ex, errors)
          errors.any? do |error|
            if error.respond_to?(:name) && error.is_a?(Class)
              ex.class == error || ex.class < error
            else
              ex.class.name == error
            end
          end
        end

        def self.callback
          @@callback
        end

        def self.callback=(callback_lambda)
          @@callback = callback_lambda
        end
      end
    end
  end
end
