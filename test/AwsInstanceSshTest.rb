# frozen_string_literal: true

require 'test/unit'
require 'stringio'

$LOADED_FEATURES << 'net/ssh' unless $LOADED_FEATURES.include?('net/ssh')
$LOADED_FEATURES << 'net/scp' unless $LOADED_FEATURES.include?('net/scp')

unless defined?(Net::SSH)
  module Net
    module SSH
      def self.start(*)
        yield self
      end

      def self.scp
        self
      end

      def self.upload!(*); end
      def self.exec!(*); end
    end

    module SCP
      def self.upload!(*); end
    end
  end
end

require_relative '../betterez/AwsInstance'

class AwsInstanceSshTest < Test::Unit::TestCase
  InstanceMock = Struct.new(:instance_id, :instance_type, :tags, :public_ip_address, :private_ip_address)

  class FakeSession
    def initialize(output, exit_code)
      @output = output
      @exit_code = exit_code
    end

    def exec!(_command, status: nil)
      status[:exit_code] = @exit_code if status
      @output
    end
  end

  class StatusSession
    attr_reader :commands

    def initialize(*replies)
      @replies = replies
      @commands = []
    end

    def exec!(command, **)
      @commands << command
      @replies.shift
    end
  end

  class FakeExitStatus
    def initialize(code)
      @code = code
    end

    def read_long
      @code
    end
  end

  class FakeSignal
    def initialize(name)
      @name = name
    end

    def read_string
      @name
    end
  end

  class FakeChannel
    attr_reader :executed, :eof_sent, :shell_requested

    def initialize(stdout:, stderr:, exit_code:, exit_signal: nil)
      @stdout = stdout
      @stderr = stderr
      @exit_code = exit_code
      @exit_signal = exit_signal
      @request_handlers = {}
    end

    def exec(command)
      @executed = command
      yield(self, true) if block_given?
    end

    def send_channel_request(name, *)
      @shell_requested = true if name == 'shell'
    end

    def request_pty(*); end

    def send_data(*); end

    def eof!
      @eof_sent = true
    end

    def on_data(&block)
      @on_data = block
    end

    def on_extended_data(&block)
      @on_extended_data = block
    end

    def on_request(name, &block)
      @request_handlers[name] = block
    end

    def on_eof(&block)
      @on_eof = block
    end

    def on_close(&block)
      @on_close = block
    end

    def wait
      @on_data&.call(self, @stdout) if @stdout
      @on_extended_data&.call(self, 1, @stderr) if @stderr
      @request_handlers['exit-signal']&.call(self, FakeSignal.new(@exit_signal)) if @exit_signal
      @request_handlers['exit-status']&.call(self, FakeExitStatus.new(@exit_code)) unless @exit_code.nil?
      @on_eof&.call(self)
      @on_close&.call(self)
    end
  end

  class FakeChannelSession
    def initialize(channel)
      @channel = channel
    end

    def open_channel
      yield @channel
      @channel
    end
  end

  def stub_ssh_channel(stdout: 'out', stderr: nil, exit_code: 0, exit_signal: nil)
    channel = FakeChannel.new(stdout: stdout, stderr: stderr, exit_code: exit_code, exit_signal: exit_signal)
    Net::SSH.define_singleton_method(:start) do |*_args, **_opts, &block|
      block.call(FakeChannelSession.new(channel))
    end
    channel
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  def setup
    @instance = AwsInstance.new(InstanceMock.new('i-test', 't4g.small', [], nil, '10.0.0.1'), { staging: { keyPath: '/tmp/key' } })
    @instance.environment = 'staging'
    @original_start = Net::SSH.method(:start)
  end

  def teardown
    Net::SSH.define_singleton_method(:start, @original_start)
  end

  # Each element of +outcomes+ is either an exception to raise or a FakeSession to yield.
  def stub_ssh(outcomes)
    calls = []
    Net::SSH.define_singleton_method(:start) do |*args, **_opts, &block|
      calls << args
      outcome = outcomes.shift
      raise outcome if outcome.is_a?(Exception)

      block.call(outcome)
    end
    calls
  end

  def test_run_ssh_command_stops_retrying_after_success_following_failure
    calls = stub_ssh([StandardError.new('refused'), FakeSession.new('ok', 0), FakeSession.new('again', 0)])

    result = @instance.run_ssh_command('ls', 5, 0)

    assert_equal('ok', result)
    assert_equal(2, calls.length)
  end

  def test_run_ssh_command_bang_returns_output_on_success
    stub_ssh([FakeSession.new('57', 0)])

    assert_equal('57', @instance.run_ssh_command!('echo 57', 1, 0))
  end

  def test_run_ssh_command_bang_raises_on_non_zero_exit
    stub_ssh([FakeSession.new('permission denied', 1)])

    error = assert_raise(RuntimeError) { @instance.run_ssh_command!('false', 1, 0) }
    assert_match(/exit code 1/, error.message)
  end

  def test_run_ssh_command_bang_retries_connection_errors_then_raises
    calls = stub_ssh([StandardError.new('refused'), StandardError.new('refused')])

    error = assert_raise(RuntimeError) { @instance.run_ssh_command!('ls', 2, 0) }
    assert_match(/refused/, error.message)
    assert_equal(2, calls.length)
  end

  def test_run_ssh_command_bang_retries_connection_error_then_succeeds
    stub_ssh([StandardError.new('refused'), FakeSession.new('ok', 0)])

    assert_equal('ok', @instance.run_ssh_command!('ls', 3, 0))
  end

  def test_run_ssh_in_terminal_execs_command_and_closes_stdin
    channel = stub_ssh_channel

    capture_stdout { @instance.run_ssh_in_terminal('cd /home/bz-app/svc && pnpm i') }

    assert_equal('cd /home/bz-app/svc && pnpm i', channel.executed)
    assert(channel.eof_sent)
    assert_nil(channel.shell_requested)
  end

  def test_run_ssh_in_terminal_prints_stderr
    stub_ssh_channel(stdout: 'Progress: resolved 10', stderr: 'ERR_PNPM_FETCH_404 btrz-monitoring', exit_code: 0)

    output = capture_stdout { @instance.run_ssh_in_terminal('pnpm i') }

    assert_match(/Progress: resolved 10/, output)
    assert_match(/ERR_PNPM_FETCH_404 btrz-monitoring/, output)
  end

  def test_run_ssh_in_terminal_raises_on_non_zero_exit
    stub_ssh_channel(stderr: 'ERR_PNPM', exit_code: 1)

    error = assert_raise(RuntimeError) { capture_stdout { @instance.run_ssh_in_terminal('pnpm i') } }
    assert_match(/exited with status 1/, error.message)
  end

  def test_run_ssh_in_terminal_raises_without_exit_status
    stub_ssh_channel(exit_code: nil)

    error = assert_raise(RuntimeError) { capture_stdout { @instance.run_ssh_in_terminal('pnpm i') } }
    assert_match(/without exit status/, error.message)
  end

  def test_run_ssh_in_terminal_prints_exit_signal
    stub_ssh_channel(exit_code: nil, exit_signal: 'TERM')
    original = $stdout
    captured = StringIO.new
    $stdout = captured
    error = assert_raise(RuntimeError) { @instance.run_ssh_in_terminal('pnpm i') }
    assert_match(/Error: TERM/, captured.string)
    assert_match(/without exit status/, error.message)
  ensure
    $stdout = original
  end

  def skip_sleep
    @instance.define_singleton_method(:sleep) { |*| }
  end

  def test_run_ssh_command_with_status_returns_when_background_job_finishes
    skip_sleep
    start = StatusSession.new("4321\n")
    poll = StatusSession.new("added 10 packages\n", "FINISHED\n")
    stub_ssh([start, poll])

    result = nil
    output = capture_stdout { result = @instance.run_ssh_command_with_status('npm install') }

    assert_equal('', result)
    assert_match(/Started background job with PID: 4321/, output)
    assert_match(/SUCCESS: npm install completed!/, output)
    assert_equal(['nohup npm install > /tmp/script.log 2>&1 & echo $!'], start.commands)
    assert_equal(['tail -n 20 /tmp/script.log', "kill -0 4321 2>/dev/null && echo 'RUNNING' || echo 'FINISHED'"], poll.commands)
  end

  def test_run_ssh_command_with_status_keeps_polling_while_running
    slept = []
    @instance.define_singleton_method(:sleep) { |seconds| slept << seconds }
    running = StatusSession.new("npm ERR! still installing\n", "RUNNING\n")
    finished = StatusSession.new("added 10 packages\n", "FINISHED\n")
    stub_ssh([StatusSession.new('99'), running, finished])

    capture_stdout { @instance.run_ssh_command_with_status('npm install') }

    assert_equal([10, 10], slept)
    assert_equal("kill -0 99 2>/dev/null && echo 'RUNNING' || echo 'FINISHED'", running.commands.last)
  end

  def test_run_ssh_command_with_status_raises_when_log_shows_npm_failure
    skip_sleep
    ['npm ERR! code E404', 'npm error code E404', 'bash: npm: command not found'].each do |log|
      stub_ssh([StatusSession.new("7\n"), StatusSession.new(log, "FINISHED\n")])

      error = assert_raise(RuntimeError) do
        capture_stdout { @instance.run_ssh_command_with_status('npm install') }
      end
      assert_equal('npm install failed!', error.message)
    end
  end

  def test_run_ssh_command_with_status_raises_after_ninety_polls
    skip_sleep
    polls = 0
    Net::SSH.define_singleton_method(:start) do |*_args, **_opts, &block|
      replies = polls.zero? ? ["55\n"] : ['still going', "RUNNING\n"]
      polls += 1
      block.call(StatusSession.new(*replies))
    end

    error = assert_raise(RuntimeError) do
      capture_stdout { @instance.run_ssh_command_with_status('npm install') }
    end

    assert_equal('Command timed out after 15 minutes', error.message)
    assert_equal(91, polls)
  end

  def test_run_queued_ssh_command_retries_failed_terminal_command_until_success
    attempts = 0
    @instance.define_singleton_method(:run_ssh_in_terminal) do |_command|
      attempts += 1
      raise 'command exited with status 1' if attempts == 1
    end

    capture_stdout { @instance.run_queued_ssh_command('pnpm i', true, 0.01, 10) }

    assert_equal(2, attempts)
  end

  def test_run_queued_ssh_command_raises_after_five_failed_attempts
    attempts = 0
    @instance.define_singleton_method(:run_ssh_in_terminal) do |_command|
      attempts += 1
      raise 'command exited with status 1'
    end

    error = assert_raise(RuntimeError) { capture_stdout { @instance.run_queued_ssh_command('pnpm i', true, 0.01, 10) } }
    assert_match(/pnpm i/, error.message)
    assert_equal(5, attempts)
  end

  def test_run_queued_ssh_command_kills_attempt_after_max_polls_and_retries
    attempts = 0
    @instance.define_singleton_method(:run_ssh_in_terminal) do |_command|
      attempts += 1
      sleep 5 if attempts == 1
    end

    output = capture_stdout { @instance.run_queued_ssh_command('pnpm i', true, 0.01, 3) }

    assert_equal(2, attempts)
    assert_match(/COMMAND KILLED: pnpm i/, output)
  end

  def test_write_build_number_file_raises_when_build_number_missing
    [nil, '', '  '].each do |missing|
      assert_raise(ArgumentError) { @instance.write_build_number_file(missing) }
    end
  end

  def test_write_build_number_file_writes_zero
    commands = []
    @instance.define_singleton_method(:run_ssh_command!) do |command, *|
      commands << command
      ''
    end

    @instance.write_build_number_file('0')

    assert_equal(['echo 0 | sudo tee /home/bz-app/build_number.txt'], commands)
  end

  def test_update_build_number_does_not_write_build_number_file
    commands = []
    instance = @instance
    instance.define_singleton_method(:run_ssh_command) do |command, *|
      commands << command
      ''
    end
    instance.define_singleton_method(:run_ssh_command!) do |command, *|
      commands << command
      ''
    end
    ec2 = Object.new
    def ec2.create_tags(**); end
    original_client = Helpers.method(:create_aws_ec2_client)
    Helpers.define_singleton_method(:create_aws_ec2_client) { |*| ec2 }
    begin
      instance.update_build_number(
        {
          build_number: 57,
          'applications' => [{ 'deployment' => { 'service_name' => 'svc' }, 'machine' => { 'daemon_type' => 'systemd' } }]
        }
      )
    ensure
      Helpers.define_singleton_method(:create_aws_ec2_client, original_client)
    end

    assert(commands.none? { |c| c.include?('build_number.txt') })
    assert(commands.include?('sudo systemctl restart svc.service'))
  end
end
