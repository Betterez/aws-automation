#!/usr/bin/ruby
require "test/unit"
require_relative "../betterez/SecretsManager"

class SecretsManagerTest < Test::Unit::TestCase
    def setup
        @manager=SecretsManager.new
    end

    def test_default_engine
        assert_equal(@manager.get_engine,"aws")
    end
end