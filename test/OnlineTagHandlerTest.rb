# frozen_string_literal: true

require 'test/unit'
require_relative '../betterez/OnlineTagHandler'

class OnlineTagHandlerTest < Test::Unit::TestCase
  class Host
    include OnlineTagHandler

    attr_reader :tag_updates, :ssh_commands, :notifications

    def initialize
      @tag_updates = []
      @ssh_commands = []
      @notifications = []
    end

    def update_tag_value(tag_name, tag_value)
      @tag_updates << [tag_name, tag_value]
    end

    def run_ssh_command(ssh_command, _loops = 5, _command_delay = 5)
      @ssh_commands << ssh_command
      ''
    end

    def notify(message)
      @notifications << message
    end
  end

  def setup
    @host = Host.new
  end

  def test_apply_online_tag_yes_restarts_startup_download
    @host.apply_online_tag(true)

    assert_equal([['Online', 'yes']], @host.tag_updates)
    assert_equal(['sudo systemctl restart startup-download.service'], @host.ssh_commands)
  end

  def test_apply_online_tag_no_does_not_restart_startup_download
    @host.apply_online_tag(false)

    assert_equal([['Online', 'no']], @host.tag_updates)
    assert_equal([], @host.ssh_commands)
  end

  def test_apply_online_tag_yes_does_not_raise_when_restart_fails
    def @host.run_ssh_command(*)
      raise 'ssh failed'
    end

    assert_nothing_raised { @host.apply_online_tag(true) }
    assert_equal([['Online', 'yes']], @host.tag_updates)
    assert(@host.notifications.any? { |message| message.include?('failed to restart startup-download') })
  end
end
