require 'sidekiq/processor'

RSpec.describe Sidekiq::Middleware::Server::Freekiqs do
  class NonArgumentError < StandardError; end

  def build_job_hash(worker_class, args=[])
    {'class' => worker_class, 'args' => args}
  end

  def fetch_retry_job
    retry_set = Sidekiq::RetrySet.new
    retry_job = retry_set.first
    retry_set.clear
    retry_job
  end

  def process_job(job_hash)
    mgr = instance_double('Manager', options: {:queues => ['default']})
    processor = ::Sidekiq::Processor.new(mgr)
    job_msg = Sidekiq.dump_json(job_hash)
    processor.process(Sidekiq::BasicFetch::UnitOfWork.new('queue:default', job_msg))
  end

  def initialize_middleware(middleware_opts={})
    Sidekiq.server_middleware do |chain|
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

  def cleanup_redis
    Sidekiq.redis {|c| c.flushdb }
  end

  shared_examples_for 'it should have 2 freekiqs for an ArgumentError' do
    it 'throws Freekiq exception for specified number of freekiqs' do
      args ||= []
      expect {
        process_job(build_job_hash(worker_class, args))
      }.to raise_error(Sidekiq::FreekiqException, 'Oops')
      expect(Sidekiq::RetrySet.new.size).to eq(1)
      retry_job = fetch_retry_job
      expect(retry_job['retry_count']).to eq(0)
      expect(retry_job['error_class']).to eq('Sidekiq::FreekiqException')
      expect(retry_job['error_message']).to eq('Oops')

      expect {
        process_job(retry_job.item)
      }.to raise_error(Sidekiq::FreekiqException, 'Oops')
      expect(Sidekiq::RetrySet.new.size).to eq(1)
      retry_job = fetch_retry_job
      expect(retry_job['retry_count']).to eq(1)
      expect(retry_job['error_class']).to eq('Sidekiq::FreekiqException')
      expect(retry_job['error_message']).to eq('Oops')

      expect {
        process_job(retry_job.item)
      }.to raise_error(ArgumentError, 'Oops')
      expect(Sidekiq::RetrySet.new.size).to eq(1)
      retry_job = fetch_retry_job
      expect(retry_job['retry_count']).to eq(2)
      expect(retry_job['error_class']).to eq('ArgumentError')
      expect(retry_job['error_message']).to eq('Oops')
    end
  end

  shared_examples_for 'it should have 0 freekiqs for an ArgumentError' do
    it 'raises the original error' do
      args ||= []
      expect {
        process_job(build_job_hash(worker_class, args))
      }.to raise_error(ArgumentError, 'Oops')
      expect(Sidekiq::RetrySet.new.size).to eq(1)
      retry_job = fetch_retry_job
      expect(retry_job['retry_count']).to eq(0)
      expect(retry_job['error_class']).to eq('ArgumentError')
      expect(retry_job['error_message']).to eq('Oops')
    end
  end

  shared_examples_for 'it should only raise exception for an ArgumentError' do
    it 'raises the original error' do
      args ||= []
      expect {
        process_job(build_job_hash(worker_class, args))
      }.to raise_error(ArgumentError, 'Oops')
      expect(Sidekiq::RetrySet.new.size).to eq(0)
      # Note: Sidekiq doesn't send job to morgue when retries are diabled
      expect(Sidekiq::DeadSet.new.size).to eq(0)
    end
  end

  before(:each) do
    cleanup_redis
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
      it_behaves_like 'it should only raise exception for an ArgumentError' do
        let!(:worker_class) { initialize_worker_class(freekiqs: 2, retry: false) }
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

    expect {
      process_job(build_job_hash(initialize_worker_class(freekiqs: 2)))
    }.to raise_error(Sidekiq::FreekiqException, 'Oops')
    expect(called).to eq(true)
  end

  it 'should still raise FreekiqException if the callback fails' do
    initialize_middleware(callback: ->(worker, msg, queue){raise 'callback error'})

    expect {
      process_job(build_job_hash(initialize_worker_class(freekiqs: 2)))
    }.to raise_error(Sidekiq::FreekiqException, 'Oops')
  end
end
