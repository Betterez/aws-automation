require "test/unit"
require_relative "../betterez/ServiceInstaller"
require_relative '../utils/HashOverrider'
require_relative 'mocks/AwsInstanceMock'
require_relative '../betterez/Helpers'
require 'yaml'

class ServiceInstallerTest <Test::Unit::TestCase
  def setup
    @relative_path = "./service_samples/"
    @aws_info=Helpers.load_json_data_to_hash("./settings/aws-data.json")
  end

  def test_values
    assert(@aws_info!=nil)
  end
  def test_configuration_
    overrider=HashOverrider.new
    service_settings = { build_number: "110",branch_name: "master",service_file: "service1.yml",dont_push_to_lb: false,environment: "staging"}
    machine=YAML.load_file(@relative_path+service_settings[:service_file])
    overrider.override_hash! machine,service_settings[:environment]
    service_settings.merge!(machine)
    installer=ServiceInstaller.new service_settings, service_settings
  end
  def test_service_creation
    overrider=HashOverrider.new
    service_settings = { build_number: 110,branch_name: "master",service_file: "notification-service.yml",dont_push_to_lb: false,environment: "staging"}
    machine=YAML.load_file(@relative_path+service_settings[:service_file])
    overrider.override_hash! machine,service_settings[:environment]
    service_settings.merge!(machine)
    assert(service_settings[:build_number]==110)
    installer=ServiceInstaller.new(service_settings,@aws_info)
    assert(installer.service_code.include?("ExecStart="))
    assert(installer.service_code.include?("ExecStart= /usr/bin/npm --prefix /home/bz-app/service3 start"))
    assert(installer.service_file_location=="/etc/systemd/system/service3.service")
  end
  def test_environment_flie
    overrider=HashOverrider.new
    service_settings = { build_number: 110,branch_name: "master",service_file: "notification-service.yml",dont_push_to_lb: false,environment: "staging"}
    machine=YAML.load_file(@relative_path+service_settings[:service_file])
    overrider.override_hash! machine,service_settings[:environment]
    service_settings.merge!(machine)
    environment_file_data=File.read("./configuration_files/notification-service.env")
    installer=ServiceInstaller.new(service_settings,@aws_info)
    # output=File.open("./dumps/env_output.txt","w")
    # output.write(installer.configuration_file_content)
    # output.close
    assert(installer.configuration_file_content==environment_file_data)
    assert(installer.configuration_file_location=="/home/bz-app/service3.env")
  end
  def test_service_file_content_staging
    overrider=HashOverrider.new
    service_settings = { build_number: 110,branch_name: "master",service_file: "notification-service.yml",dont_push_to_lb: false,environment: "staging"}
    machine=YAML.load_file(@relative_path+service_settings[:service_file])
    overrider.override_hash! machine,service_settings[:environment]
    service_settings.merge!(machine)
    installer=ServiceInstaller.new(service_settings,@aws_info)
    assert(installer.service_code.include?("/usr/bin/npm --prefix /home/bz-app/service3 start"))
  end

  def test_service_file_content_sandbox
    overrider=HashOverrider.new
    service_settings = { build_number: 110,branch_name: "master",service_file: "notification-service.yml",dont_push_to_lb: false,environment: "sandbox"}
    machine=YAML.load_file(@relative_path+service_settings[:service_file])
    overrider.override_hash! machine,service_settings[:environment]
    service_settings.merge!(machine)
    installer=ServiceInstaller.new(service_settings,@aws_info)
    # output_file=File.new("dumps/sandbox_service.service","w")
    # output_file.write(installer.service_code)
    # output_file.close
    assert(installer.service_code.include?("npm start"))
    assert(installer.service_code.include?("exec sudo -H -u bz-app bash"))
  end
end
