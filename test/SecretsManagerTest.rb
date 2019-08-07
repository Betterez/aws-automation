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

    def test_initial_environemnt
        assert_equal(@manager.environment,"production")
    end

    def test_initial_repository
        assert_equal(@manager.repository,nil)
    end

    def test_setting_repository
        @manager.repository="app"
        assert_equal(@manager.repository,"app")
    end
end