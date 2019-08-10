#!/usr/bin/ruby
# frozen_string_literal: true

require 'test/unit'
require_relative '../betterez/SecretsManager'
require_relative '../betterez/VaultDriver'

class VaultMigrationTest < Test::Unit::TestCase
    def initialize(test_case_class)
        super
        @vault=VaultDriver.from_secrets_file("sandbox","./settings/aws-data.json")
    end
    def setup
    end
    def test_vault_status
        assert(@vault.get_vault_status,"vault should be online")
    end
    def test_get_repos_names
        data,code=@vault.list_all_registered_repos
        assert(code>199&&code<400)
    end
    def test_get_data_for_repos
      data,code=@vault.list_all_registered_repos
      assert(code>199&&code<400)
      data["repos"].each do |repo|
        @vault.get_json
      end
    end
end
