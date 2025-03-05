# -*- encoding: utf-8 -*-

Gem::Specification.new do |gem|
  gem.name                  = 'freekiqs'
  gem.version               = '6.5.0'
  gem.authors               = ['Rob Lewis']
  gem.email                 = ['rob@bookbub.com']
  gem.summary               = 'Sidekiq middleware extending RetryJobs to allow silient errors.'
  gem.description           = 'Sidekiq middleware extending RetryJobs to allow configuring ' \
                              'how many exceptions a job can throw and be wrapped by a silenceable exception.'
  gem.homepage              = 'https://github.com/BookBub/freekiqs'
  gem.license               = 'MIT'
  gem.executables           = []
  gem.files                 = `git ls-files`.split("\n")
  gem.test_files            = `git ls-files -- spec/*`.split("\n")
  gem.require_paths         = ['lib']
  gem.required_ruby_version = '>= 2.2.2'

  gem.add_dependency             'sidekiq', '>= 6.5.0'
  gem.add_development_dependency 'rspec', '>= 3.6.0'
  gem.add_development_dependency "appraisal"
end
