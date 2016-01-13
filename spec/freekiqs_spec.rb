require 'spec_helper'
require 'celluloid'  # Getting error without this required. Should remove once this supports Sidekiq 4.x
require 'sidekiq/cli'
require 'sidekiq/middleware/server/retry_jobs'

describe Sidekiq::Middleware::Server::Freekiqs do
  class DummyWorkerPlain
    include Sidekiq::Worker
  end
  class DummyWorkerWithFreekiqsEnabled
    include Sidekiq::Worker
    sidekiq_options freekiqs: 2
  end
  class DummyWorkerWithFreekiqsDisabled
    include Sidekiq::Worker
    sidekiq_options freekiqs: false
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
  let(:worker_with_freekiqs_disabled) { DummyWorkerWithFreekiqsDisabled.new }

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

  it 'throws Freekiq exception for specified number of free kiqs' do
    handler = build_handler_chain
    worker = worker_with_freekiqs_enabled
    job = build_job

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

  it 'allows a freekiqs option in initializer' do
    handler = build_handler_chain(freekiqs: 1)
    worker = worker_plain
    job = build_job

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
        raise ArgumentError, 'not overlooked'
      end
    }.to raise_error(ArgumentError, 'not overlooked')
    expect(job['retry_count']).to eq(1)
    expect(job['error_class']).to eq('ArgumentError')
    expect(job['error_message']).to eq('not overlooked')
    expect(Sidekiq::RetrySet.new.size).to eq(2)
    expect(Sidekiq::DeadSet.new.size).to eq(0)
  end

  it 'allows explicitly disabling freekiqs' do
    handler = build_handler_chain(freekiqs: 3)
    worker = worker_with_freekiqs_disabled
    job = build_job

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

  it 'does nothing if not explicitly enabled' do
    handler = build_handler_chain
    worker = worker_plain
    job = build_job

    expect {
      handler.invoke(worker, job, 'default') do
        raise ArgumentError, 'not overlooked'
      end
    }.to raise_error(ArgumentError, 'not overlooked')
    expect(job['retry_count']).to eq(0)
    expect(job['error_class']).to eq('ArgumentError')
    expect(job['error_message']).to eq('not overlooked')
  end

  it 'does nothing if retries disabled' do
    handler = build_handler_chain
    worker = worker_with_freekiqs_enabled
    job = build_job('retry' => false)

    expect {
      handler.invoke(worker, job, 'default') do
        raise ArgumentError, 'not overlooked'
      end
    }.to raise_error(ArgumentError, 'not overlooked')
    expect(job['retry_count']).to be_nil
    expect(job['error_class']).to be_nil
    expect(job['error_message']).to be_nil
    expect(job['error_message']).to be_nil
    expect(Sidekiq::RetrySet.new.size).to eq(0)
    expect(Sidekiq::DeadSet.new.size).to eq(0)
  end
end
