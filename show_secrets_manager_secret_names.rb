#!/usr/bin/ruby
require_relative 'betterez/SecretsManager'
require_relative 'betterez/Helpers'

secrets_manager = SecretsManager.new

names = secrets_manager.get_all_secrets_names

Helpers.log "Secret names: #{names}"

exit 0
