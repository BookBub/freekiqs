require 'spec_helper'
require 'sidekiq/cli'
require 'sidekiq/middleware/server/retry_jobs'

shared_examples_for 'it should have 2 freekiqs for an ArgumentError' do
  it 'throws Freekiq exception for specified number of free kiqs' do
    expect {
      handler.invoke(worker, job, 'default') do
        raise ArgumentError, 'overlooked'
      end
    }.to raise_error(Sidekiq::FreekiqException, 'overlooked')
    expect(job['retry_count']).to eq(0)
    expect(job['error_class']).to eq('Sidekiq::FreekiqException')
    expect(job['error_message']).to eq('overlooked')
    expect {
      handler.invoke(worker, job, 'default') do
        raise ArgumentError, 'overlooked'
      end
    }.to raise_error(Sidekiq::FreekiqException, 'overlooked')
    expect(job['retry_count']).to eq(1)
    expect(job['error_class']).to eq('Sidekiq::FreekiqException')
    expect(job['error_message']).to eq('overlooked')
    expect {
      handler.invoke(worker, job, 'default') do
        raise ArgumentError, 'not overlooked'
      end
    }.to raise_error(ArgumentError, 'not overlooked')
    expect(job['retry_count']).to eq(2)
    expect(job['error_class']).to eq('ArgumentError')
    expect(job['error_message']).to eq('not overlooked')
    expect(Sidekiq::RetrySet.new.size).to eq(3)
    expect(Sidekiq::DeadSet.new.size).to eq(0)
  end
end

shared_examples_for 'it should have 0 freekiqs for an ArgumentError' do
  it 'raises the original error' do
    expect {
      handler.invoke(worker, job, 'default') do
        raise ArgumentError, 'not overlooked'
      end
    }.to raise_error(ArgumentError, 'not overlooked')
    expect(job['retry_count']).to eq(0)
    expect(job['error_class']).to eq('ArgumentError')
    expect(job['error_message']).to eq('not overlooked')
    expect(Sidekiq::RetrySet.new.size).to eq(1)
    expect(Sidekiq::DeadSet.new.size).to eq(0)
  end
end

describe Sidekiq::Middleware::Server::Freekiqs do
  class DummyWorkerPlain
    include Sidekiq::Worker
  end
  class DummyWorkerWithFreekiqsEnabled
    include Sidekiq::Worker
    sidekiq_options freekiqs: 2
  end

  def build_handler_chain(freekiq_options={}, retry_options={})
    Sidekiq::Middleware::Chain.new do |chain|
      chain.add Sidekiq::Middleware::Server::RetryJobs, retry_options
      chain.add Sidekiq::Middleware::Server::Freekiqs, freekiq_options
    end
  end

  def build_job(options={})
    {'class' => 'FreekiqDummyWorker', 'args' => [], 'retry' => true}.merge(options)
  end

  def cleanup_redis
    Sidekiq::RetrySet.new.select{|job| job.klass == 'FreekiqDummyWorker'}.each(&:delete)
    Sidekiq::DeadSet.new.clear
  end

  before(:each) do
    cleanup_redis
  end

  let(:worker_plain)                  { DummyWorkerPlain.new }
  let(:worker_with_freekiqs_enabled)  { DummyWorkerWithFreekiqsEnabled.new }

  it 'requires RetryJobs to update retry_count' do
    handler = Sidekiq::Middleware::Server::RetryJobs.new
    worker = worker_plain
    job = build_job
    expect {
      handler.call(worker, job, 'default') do
        raise 'Oops'
      end
    }.to raise_error(RuntimeError)
    expect(job['retry_count']).to eq(0)
    expect {
      handler.call(worker, job, 'default') do
        raise 'Oops'
      end
    }.to raise_error(RuntimeError)
    expect(job['retry_count']).to eq(1)
  end

  it 'should execute a defined callback' do
    Sidekiq::Middleware::Server::Freekiqs::callback = ->(worker, msg, queue) do
      return true
    end

    handler = build_handler_chain
    worker = worker_with_freekiqs_enabled
    job = build_job

    expect(Sidekiq::Middleware::Server::Freekiqs::callback).to receive(:call)
    expect {
      handler.invoke(worker, job, 'default') do
        raise ArgumentError, 'overlooked'
      end
    }.to raise_error(Sidekiq::FreekiqException, 'overlooked')
  end

  it 'should still raise FreekiqException if the callback fails' do
    Sidekiq::Middleware::Server::Freekiqs::callback = ->(worker, msg, queue) do
      raise 'callback error'
    end

    handler = build_handler_chain
    worker = worker_with_freekiqs_enabled
    job = build_job

    expect {
      handler.invoke(worker, job, 'default') do
        raise ArgumentError, 'overlooked'
      end
    }.to raise_error(Sidekiq::FreekiqException, 'overlooked')
  end

  describe 'with nothing explicitly enabled' do
    it_behaves_like 'it should have 0 freekiqs for an ArgumentError' do
      let (:handler) { build_handler_chain }
      let (:job) { build_job }
      let (:worker) do
        Class.new do
          include Sidekiq::Worker
        end.new
      end
    end
  end

  describe 'with freekiqs explicitly disabled' do
    it_behaves_like 'it should have 0 freekiqs for an ArgumentError' do
      let (:handler) { build_handler_chain(freekiqs: 3) }
      let (:job) { build_job }
      let (:worker) do
        Class.new do
          include Sidekiq::Worker
          sidekiq_options freekiqs: false
        end.new
      end
    end
  end

  describe 'with 2 freekiqs in the initializer' do
    it_behaves_like 'it should have 2 freekiqs for an ArgumentError' do
      let (:handler) { build_handler_chain(freekiqs: 2) }
      let (:job) { build_job }
      let (:worker) do
        Class.new do
          include Sidekiq::Worker
        end.new
      end
    end
  end

  describe 'with 2 freekiqs in the worker' do
    it_behaves_like 'it should have 2 freekiqs for an ArgumentError' do
      let (:handler) { build_handler_chain }
      let (:job) { build_job }
      let (:worker) do
        Class.new do
          include Sidekiq::Worker
          sidekiq_options freekiqs: 2
        end.new
      end
    end
  end

  describe 'with freekiq_for ArgumentError and 2 freekiqs in worker' do
    it_behaves_like 'it should have 2 freekiqs for an ArgumentError' do
      let (:handler) { build_handler_chain }
      let (:job) { build_job }
      let (:worker) do
        Class.new do
          include Sidekiq::Worker
          sidekiq_options freekiqs: 2, freekiq_for: [ArgumentError]
        end.new
      end
    end
  end

  describe 'with freekiq_for ArgumentError in worker and no freekiqs' do
    it_behaves_like 'it should have 0 freekiqs for an ArgumentError' do
      let (:handler) { build_handler_chain }
      let (:job) { build_job }
      let (:worker) do
        Class.new do
          include Sidekiq::Worker
          class NonArgumentError < StandardError; end
          sidekiq_options freekiqs: 2, freekiq_for: [NonArgumentError]
        end.new
      end
    end
  end

  describe 'with freekiq_for ArgumentError in worker and 2 freekiqs in initializer' do
    it_behaves_like 'it should have 2 freekiqs for an ArgumentError' do
      let (:handler) { build_handler_chain(freekiqs: 2) }
      let (:job) { build_job }
      let (:worker) do
        Class.new do
          include Sidekiq::Worker
          sidekiq_options freekiq_for: [ArgumentError]
        end.new
      end
    end
  end

  describe 'with freekiq_for ArgumentError in initializer and 2 freekiqs in initializer' do
    it_behaves_like 'it should have 2 freekiqs for an ArgumentError' do
      let (:handler) { build_handler_chain(freekiqs: 2, freekiq_for: [ArgumentError]) }
      let (:job) { build_job }
      let (:worker) do
        Class.new do
          include Sidekiq::Worker
        end.new
      end
    end
  end

  describe 'with freekiq_for ArgumentError in initializer and 2 freekiqs in worker' do
    it_behaves_like 'it should have 2 freekiqs for an ArgumentError' do
      let (:handler) { build_handler_chain(freekiq_for: [ArgumentError]) }
      let (:job) { build_job }
      let (:worker) do
        Class.new do
          include Sidekiq::Worker
          sidekiq_options freekiqs: 2
        end.new
      end
    end
  end

  describe 'with freekiq_for NonArgumentError in worker and 2 freekiqs in worker' do
    it_behaves_like 'it should have 0 freekiqs for an ArgumentError' do
      let (:handler) { build_handler_chain }
      let (:job) { build_job }
      let (:worker) do
        Class.new do
          include Sidekiq::Worker
          class NonArgumentError < StandardError; end
          sidekiq_options freekiqs: 2, freekiq_for: [NonArgumentError]
        end.new
      end
    end
  end

  describe 'with freekiq_for NonArgumentError in initializer and 2 freekiqs in worker' do
    it_behaves_like 'it should have 0 freekiqs for an ArgumentError' do
      let (:handler) { build_handler_chain(freekiq_for: [NonArgumentError]) }
      let (:job) { build_job }
      let (:worker) do
        Class.new do
          include Sidekiq::Worker
          class NonArgumentError < StandardError; end
          sidekiq_options freekiqs: 2
        end.new
      end
    end
  end

  describe 'with freekiq_for NonArgumentError in initializer and freekiq for ArgumentError in worker' do
    it_behaves_like 'it should have 2 freekiqs for an ArgumentError' do
      let (:handler) { build_handler_chain(freekiq_for: [NonArgumentError]) }
      let (:job) { build_job }
      let (:worker) do
        Class.new do
          include Sidekiq::Worker
          sidekiq_options freekiqs: 2, freekiq_for: [ArgumentError]
        end.new
      end
    end
  end

  describe 'with freekiq_for ArgumentError in initializer and freekiq for NonArgumentError in worker' do
    it_behaves_like 'it should have 0 freekiqs for an ArgumentError' do
      let (:handler) { build_handler_chain(freekiq_for: [ArgumentError]) }
      let (:job) { build_job }
      let (:worker) do
        Class.new do
          include Sidekiq::Worker
          class NonArgumentError < StandardError; end
          sidekiq_options freekiqs: 2, freekiq_for: [NonArgumentError]
        end.new
      end
    end
  end

  describe 'with freekiq_for ArgumentError as a string' do
    it_behaves_like 'it should have 2 freekiqs for an ArgumentError' do
      let (:handler) { build_handler_chain }
      let (:job) { build_job }
      let (:worker) do
        Class.new do
          include Sidekiq::Worker
          sidekiq_options freekiqs: 2, freekiq_for: ['ArgumentError']
        end.new
      end
    end
  end

  describe 'with freekiq_for the super class of ArgumentError' do
    it_behaves_like 'it should have 2 freekiqs for an ArgumentError' do
      let (:handler) { build_handler_chain }
      let (:job) { build_job }
      let (:worker) do
        Class.new do
          include Sidekiq::Worker
          sidekiq_options freekiqs: 2, freekiq_for: [ArgumentError.superclass]
        end.new
      end
    end
  end
end
