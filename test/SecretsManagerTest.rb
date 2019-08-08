#!/usr/bin/ruby
require "test/unit"
require_relative "../betterez/SecretsManager"

class SecretsManagerTest < Test::Unit::TestCase
    def setup
        @manager=SecretsManager.new
    end
    private
    def compose_secret_name
    end
    public
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
        assert_equal(@manager.repository,"app","repository should be assignable")
    end
    def test_get_json_throws_without_repo
        setup
        assert_throw(SecretsManager::NO_REPO) do
            @manager.get_json
        end
    end
    def test_get_json
        # omit
        setup
        @manager.repository="btrz-api-loyalty"
        data,code=@manager.get_json
        assert_equal(code,200)
        assert_equal(data["username"],"loyalty_user")
    end

    # private compose_secret_name
end
