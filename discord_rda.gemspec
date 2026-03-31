# frozen_string_literal: true

require_relative 'lib/discord_rda/version'

Gem::Specification.new do |spec|
  spec.name          = 'discord_rda'
  spec.version       = DiscordRDA::VERSION
  spec.authors       = ['Júlia Klee']
  spec.email         = ['julia@nda.nda']
  spec.summary       = 'Modern, scalable Ruby library for Discord bots'
  spec.description   = 'DiscordRDA (Ruby Development API) is a modern, scalable Ruby library for Discord bot development '
                       'featuring factory patterns, async runtime, and modular architecture.'
  spec.homepage      = 'https://github.com/juliaklee/discord_rda'
  spec.license       = 'Júlia Klee License'

  spec.required_ruby_version = '>= 3.0.0'

  spec.files         = Dir['lib/**/*', 'LICENSE', 'README.md', 'CHANGELOG.md']
  spec.require_paths = ['lib']

  # Core dependencies
  spec.add_dependency 'async', '~> 2.21'
  spec.add_dependency 'async-http', '~> 0.86'
  spec.add_dependency 'async-websocket', '~> 0.30'
  spec.add_dependency 'oj', '~> 3.16'
  spec.add_dependency 'timers', '~> 4.3'
  spec.add_dependency 'multipart-post', '~> 2.4'

  # Optional dependencies
  spec.add_dependency 'redis', '~> 5.2'
  spec.add_dependency 'listen', '~> 3.9'
  spec.add_dependency 'console', '~> 1.29'

  # Development dependencies
  spec.add_development_dependency 'async-rspec', '~> 1.17'
  spec.add_development_dependency 'rake', '~> 13.2'
  spec.add_development_dependency 'rspec', '~> 3.13'
  spec.add_development_dependency 'rubocop', '~> 1.71'
  spec.add_development_dependency 'webmock', '~> 3.24'
  spec.add_development_dependency 'yard', '~> 0.9'
end
