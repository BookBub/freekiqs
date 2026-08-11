# Changelog

## [Unreleased]

## [6.6.0] - 2026-08-10

* Support Sidekiq 8 (#19)
* Introduce the appraisal gem so the suite runs against multiple Sidekiq versions (#18)
* Test against Sidekiq 7 (#10)
* Test against Ruby 3.2, 3.3 and 3.4 (#17), dropping support for Ruby 3.1 (#15)
* Test using Sidekiq's fake testing mode (#12)
* Change logger setup (#9)
* Move CI from CircleCI to GitHub Actions (#11)
* Check in `Gemfile.lock` (#16)
* Migrate from `shell.nix` to `flake.nix`, upgrading to nixpkgs 26.05 and ruby 4.0
* Add ruby 4.0 to the CI matrix
* Update dependent gems and drop stale entries from the lockfile's platform list
* Drop the unused `Vagrantfile`

## [6.5.0] - 2022-10-11

* Support Sidekiq 6.5 and higher (#7)
* Rails 5 compatibility (#6)

## [5.0.0] - 2017-08-03

* Update to work with Sidekiq v5+

## [4.1.0] - 2016-06-24

* Add a `freekiq_for` option, letting specific errors be defined as the only errors that will
  freekiq (#5)

## [4.0.0] - 2016-06-21

* Allow Sidekiq v4
* Switch `sidekiq_options` to use the getter, `get_sidekiq_options` (#3)

## [0.2.0] - 2016-01-26

* Add an optional callback for each freekiq (#1)
* Relax the version dependency for rspec

## [0.1.0] - 2016-01-26

* Initial release
