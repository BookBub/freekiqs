require 'sidekiq'
require 'sidekiq/testing'

RSpec.describe Sidekiq::Middleware::Server::Freekiqs do
  class NonArgumentError < StandardError; end

  module Sidekiq
    module Middleware
      module Server
        class FakeTestModeEnqueueFailuresForRetry
          def call(job_instance, job_payload, queue)
            begin
              yield
            rescue => ex
              if job_payload["retry"]
                if job_payload["retry_count"]
                  job_payload["retry_count"] += 1
                else
                  job_payload["retry_count"] = 0
                end

                max_retries = Sidekiq.default_configuration[:max_retries] || 25
                raise if job_payload["retry_count"] >= max_retries

                job_payload["queue"] = "retry"
                job_payload["exception_class"] = ex.class

                Sidekiq::Client.push(job_payload)
              else
                raise
              end
            end
          end
        end
      end
    end
  end

  before do
    Sidekiq::Worker.clear_all
    Sidekiq::Testing.fake!
  end

  def initialize_middleware(middleware_opts={})
    Sidekiq::Testing.server_middleware do |chain|
      chain.add Sidekiq::Middleware::Server::FakeTestModeEnqueueFailuresForRetry
      chain.add Sidekiq::Middleware::Server::Freekiqs, middleware_opts
    end
  end

  def initialize_worker_class(sidekiq_opts=nil)
    worker_class_name = :TestDummyWorker
    Object.send(:remove_const, worker_class_name) if Object.const_defined?(worker_class_name)
    klass = Class.new do
      include Sidekiq::Worker
      sidekiq_options sidekiq_opts if sidekiq_opts
      def perform
        raise ArgumentError, 'Oops'
      end
    end
    Object.const_set(worker_class_name, klass)
  end

  shared_examples_for 'it should have 2 freekiqs for an ArgumentError' do
    it 'throws Freekiq exception for specified number of freekiqs' do
      worker_class.perform_async
      worker_class.perform_one
      expect(worker_class.jobs).to match_array(
        a_hash_including(
          "queue" => "retry",
          "retry_count" => 0,
          "exception_class" => "Sidekiq::FreekiqException",
        ),
      )

      worker_class.perform_one
      expect(worker_class.jobs).to match_array(
        a_hash_including(
          "queue" => "retry",
          "retry_count" => 1,
          "exception_class" => "Sidekiq::FreekiqException",
        ),
      )

      worker_class.perform_one
      expect(worker_class.jobs).to match_array(
        a_hash_including(
          "queue" => "retry",
          "retry_count" => 2,
          "exception_class" => "ArgumentError",
        ),
      )
    end
  end

  shared_examples_for 'it should have 0 freekiqs for an ArgumentError' do
    it 'raises the original error' do
      worker_class.perform_async
      worker_class.perform_one
      expect(worker_class.jobs).to match_array(
        a_hash_including(
          "queue" => "retry",
          "retry_count" => 0,
          "exception_class" => "ArgumentError",
        ),
      )
    end
  end

  context 'with default middleware config' do
    before(:each) do
      initialize_middleware
    end

    describe 'with nothing explicitly enabled' do
      it_behaves_like 'it should have 0 freekiqs for an ArgumentError' do
        let!(:worker_class) { initialize_worker_class }
      end
    end

    describe 'with freekiqs explicitly disabled' do
      it_behaves_like 'it should have 0 freekiqs for an ArgumentError' do
        let!(:worker_class) { initialize_worker_class(freekiqs: false) }
      end
    end

    describe 'with 2 freekiqs in the worker' do
      it_behaves_like 'it should have 2 freekiqs for an ArgumentError' do
        let!(:worker_class) { initialize_worker_class(freekiqs: 2) }
      end
    end

    describe 'with freekiq_for ArgumentError and 2 freekiqs in worker' do
      it_behaves_like 'it should have 2 freekiqs for an ArgumentError' do
        let!(:worker_class) { initialize_worker_class(freekiqs: 2, freekiq_for: [ArgumentError]) }
      end
    end

    describe 'with freekiq_for ArgumentError in worker and no freekiqs' do
      it_behaves_like 'it should have 0 freekiqs for an ArgumentError' do
        let!(:worker_class) { initialize_worker_class(freekiqs: false, freekiq_for: [ArgumentError]) }
      end
    end

    describe 'with freekiq_for NonArgumentError in worker and 2 freekiqs in worker' do
      it_behaves_like 'it should have 0 freekiqs for an ArgumentError' do
        let!(:worker_class) { initialize_worker_class(freekiqs: 2, freekiq_for: [NonArgumentError]) }
      end
    end

    describe 'with freekiq_for ArgumentError as a string' do
      it_behaves_like 'it should have 2 freekiqs for an ArgumentError' do
        let!(:worker_class) { initialize_worker_class(freekiqs: 2, freekiq_for: ['ArgumentError']) }
      end
    end

    describe 'with freekiq_for the super class of ArgumentError' do
      it_behaves_like 'it should have 2 freekiqs for an ArgumentError' do
        let!(:worker_class) { initialize_worker_class(freekiqs: 2, freekiq_for: [ArgumentError.superclass]) }
      end
    end

    describe 'with 2 freekiqs in the worker and retries disabled' do
      let!(:worker_class) { initialize_worker_class(freekiqs: 2, retry: false) }

      it 'raises the original error' do
        worker_class.perform_async
        expect { worker_class.perform_one }.to raise_error(ArgumentError, 'Oops')

        expect(worker_class.jobs.size).to eq 0
      end
    end
  end

  context 'with middleware configured with 2 freekiqs' do
    before(:each) do
      initialize_middleware(freekiqs: 2)
    end

    it_behaves_like 'it should have 2 freekiqs for an ArgumentError' do
      let!(:worker_class) { initialize_worker_class }
    end

    describe 'with freekiq_for ArgumentError in worker' do
      it_behaves_like 'it should have 2 freekiqs for an ArgumentError' do
        let!(:worker_class) { initialize_worker_class(freekiq_for: [ArgumentError]) }
      end
    end
  end

  context 'with middleware configured with freekiq_for ArgumentError' do
    before(:each) do
      initialize_middleware(freekiq_for: [ArgumentError])
    end

    describe 'with 2 freekiqs in worker' do
      it_behaves_like 'it should have 2 freekiqs for an ArgumentError' do
        let!(:worker_class) { initialize_worker_class(freekiqs: 2) }
      end
    end

    describe 'with freekiq_for NonArgumentError in worker' do
      it_behaves_like 'it should have 0 freekiqs for an ArgumentError' do
        let!(:worker_class) { initialize_worker_class(freekiqs: 2, freekiq_for: [NonArgumentError]) }
      end
    end
  end

  context 'with middleware configured with freekiq_for NonArgumentError' do
    before(:each) do
      initialize_middleware(freekiq_for: [NonArgumentError])
    end

    describe 'with 2 freekiqs in worker' do
      it_behaves_like 'it should have 0 freekiqs for an ArgumentError' do
        let!(:worker_class) { initialize_worker_class(freekiqs: 2) }
      end
    end

    describe 'with freekiq_for ArgumentError in worker' do
      it_behaves_like 'it should have 2 freekiqs for an ArgumentError' do
        let!(:worker_class) { initialize_worker_class(freekiqs: 2, freekiq_for: [ArgumentError]) }
      end
    end
  end

  context 'with middleware configured with 2 freekiqs and freekiq_for ArgumentError' do
    before(:each) do
      initialize_middleware(freekiqs: 2, freekiq_for: [ArgumentError])
    end

    it_behaves_like 'it should have 2 freekiqs for an ArgumentError' do
      let!(:worker_class) { initialize_worker_class }
    end
  end

  it 'should execute a defined callback' do
    called = false
    initialize_middleware(callback: ->(worker, msg, queue){called = true})

    worker_class = initialize_worker_class(freekiqs: 2)
    worker_class.perform_async
    worker_class.perform_one

    expect(worker_class.jobs).to match_array(
      a_hash_including(
        "queue" => "retry",
        "retry_count" => 0,
        "exception_class" => "Sidekiq::FreekiqException",
      ),
    )

    expect(called).to eq(true)
  end

  it 'should still raise FreekiqException if the callback fails' do
    initialize_middleware(callback: ->(worker, msg, queue){raise 'callback error'})

    worker_class = initialize_worker_class(freekiqs: 2)
    worker_class.perform_async
    worker_class.perform_one

    expect(worker_class.jobs).to match_array(
      a_hash_including(
        "queue" => "retry",
        "retry_count" => 0,
        "exception_class" => "Sidekiq::FreekiqException",
      ),
    )
  end
end
