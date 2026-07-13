# frozen_string_literal: true

require 'test/unit'
require_relative '../betterez/ServiceSetupNormalizer'

class ServiceSetupNormalizerTest < Test::Unit::TestCase
  def legacy_setup
    {
      'deployment' => {
        'service_name' => 'svc-a',
        'healthcheck' => { 'perform' => true, 'command' => 'c', 'result' => 'ok' },
        'source' => { 'type' => 'git', 'repo' => 'r', 'branch_name' => 'master' }
      },
      'machine' => { 'image' => 'img-legacy', 'daemon_type' => 'systemd', 'start' => 'npm start' }
    }
  end

  def test_applications_list_implicit_single
    s = legacy_setup
    list = ServiceSetupNormalizer.applications_list(s)
    assert_equal(1, list.length)
    assert_equal('svc-a', list[0]['deployment']['service_name'])
  end

  def test_infrastructure_primary_last_with_healthcheck
    s = {
      'deployment' => {},
      'machine' => { 'image' => 'ami1' },
      'applications' => [
        {
          'deployment' => {
            'service_name' => 'bpe',
            'healthcheck' => { 'perform' => false },
            'source' => { 'type' => 'git', 'repo' => 'x', 'branch_name' => 'main' }
          },
          'machine' => { 'daemon_type' => 'systemd', 'start' => 's1' }
        },
        {
          'deployment' => {
            'service_name' => 'facade',
            'healthcheck' => { 'perform' => true, 'command' => 'curl', 'result' => '200' },
            'source' => { 'type' => 'git', 'repo' => 'y', 'branch_name' => 'master' }
          },
          'machine' => { 'daemon_type' => 'systemd', 'start' => 's2' }
        }
      ]
    }
    assert_equal('facade', ServiceSetupNormalizer.infrastructure_primary_service_name(s))
    assert_equal(1, ServiceSetupNormalizer.infrastructure_primary_index(s))
  end

  def test_infrastructure_primary_falls_back_to_last_when_no_healthcheck
    s = {
      'deployment' => {},
      'machine' => {},
      'applications' => [
        {
          'deployment' => {
            'service_name' => 'a',
            'healthcheck' => { 'perform' => false },
            'source' => { 'type' => 'nop' }
          },
          'machine' => {}
        },
        {
          'deployment' => {
            'service_name' => 'z',
            'healthcheck' => { 'perform' => false },
            'source' => { 'type' => 'nop' }
          },
          'machine' => {}
        }
      ]
    }
    assert_equal('z', ServiceSetupNormalizer.infrastructure_primary_service_name(s))
  end

  def test_machine_image_for_ami_prefers_root_then_apps
    s = {
      'deployment' => {},
      'machine' => { 'image' => 'from-root' },
      'applications' => [
        { 'deployment' => {}, 'machine' => { 'image' => 'ignored' } }
      ]
    }
    assert_equal('from-root', ServiceSetupNormalizer.machine_image_for_ami(s))

    s2 = {
      'deployment' => {},
      'machine' => {},
      'applications' => [
        { 'deployment' => {}, 'machine' => {} },
        { 'deployment' => {}, 'machine' => { 'image' => 'from-app' } }
      ]
    }
    assert_equal('from-app', ServiceSetupNormalizer.machine_image_for_ami(s2))
  end

  def test_merged_app_service_setup
    root = {
      :environment => 'staging',
      :build_number => 42,
      'deployment' => { 'legacy' => true },
      'machine' => { 'shared' => true },
      'applications' => []
    }
    app = {
      'deployment' => { 'service_name' => 'app1' },
      'machine' => { 'start' => 'run' }
    }
    m = ServiceSetupNormalizer.merged_app_service_setup(root, app)
    assert_equal('staging', m[:environment])
    assert_equal(42, m[:build_number])
    assert_equal('app1', m['deployment']['service_name'])
    assert_equal('run', m['machine']['start'])
    assert(!m.key?('applications'))
  end

  def test_sync_root_deployment_and_machine
    s = {
      'deployment' => { 'service_name' => 'old', 'path_name' => 'x' },
      'machine' => { 'image' => 'ami-x', 'servers_count' => 2 },
      'applications' => [
        {
          'deployment' => { 'service_name' => 'b', 'path_name' => 'bpath' },
          'machine' => { 'daemon_type' => 'systemd' }
        },
        {
          'deployment' => { 'service_name' => 'facade', 'path_name' => '/api', 'healthcheck' => { 'perform' => true } },
          'machine' => { 'start' => 'npm' }
        }
      ]
    }
    ServiceSetupNormalizer.sync_root_deployment_and_machine!(s)
    assert_equal('facade', s['deployment']['service_name'])
    assert_equal('/api', s['deployment']['path_name'])
    assert_equal('ami-x', s['machine']['image'])
    assert_equal(2, s['machine']['servers_count'])
    assert_equal('npm', s['machine']['start'])
  end
end
