require_relative 'Helpers'
require_relative 'Notifire'
require_relative 'VaultDriver'
require_relative 'AwsInstance'
require_relative 'SecurityChecker'

class ServiceInstaller
  @service_code = ''
  attr_reader(:has_configuration_file)
  attr_reader(:service_code)
  attr_reader(:configuration_file_content)
  attr_reader(:configuration_file_location)
  attr_reader(:service_type)
  attr_reader(:service_file_location)
  attr_accessor(:service_setup_data)

  def initialize(service_setup_data, aws_settings_data)
    @service_setup_data = service_setup_data
    run_command = service_setup_data['machine']['start']
    environment_variables = ''
    vault_data = ''
    @configuration_file_content = ''
    if service_setup_data['machine'].key?('environment_variables')
      service_setup_data['machine']['environment_variables'].each do |environment_variable|
        environment_variables += "#{environment_variable} "
      end
    end

    if aws_settings_data.key? :vault
      puts 'loading data from vault'
      driver = VaultDriver.from_secrets_file @service_setup_data[:environment]
      if aws_settings_data.key?(:secrets)
        puts 'vault unlocked' if driver.unlock_vault(aws_settings_data[:secrets][:vault][:keys]) == 200
      else
        puts 'no vault secrets file.'
      end
      driver.get_vault_status
      if driver.online && !driver.locked
        vault_data = driver.get_system_variables_for_service(service_setup_data['deployment']['service_name'])
        if !vault_data.nil? && vault_data != ''
          puts 'vault data loaded'
        else
          puts "vault data= #{vault_data}"
        end
      end
    else
      puts "no vault data for this repo in this environment #{@service_setup_data[:environment]}"
    end

    case service_setup_data['machine']['daemon_type']
    when 'upstart'
      @has_configuration_file = false
      generate_upstart_service_code(run_command)
      @service_file_location = "/etc/init/#{service_setup_data['deployment']['service_name']}.conf"
      @service_type = 'upstart'
      @service_code.gsub!('[environment_variables]', environment_variables)
      @service_code.gsub!('[vault_data]', vault_data)
    when 'systemd'
      generate_systemd_service_code
      @service_type = 'systemd'
      @service_file_location = "/etc/systemd/system/#{service_setup_data['deployment']['service_name']}.service"
      @has_configuration_file = true
      @configuration_file_location = "/home/bz-app/#{service_setup_data['deployment']['service_name']}.env"
      if service_setup_data['machine'].key? 'runner_command'
        @service_code.gsub!('[runner_command]', service_setup_data['machine']['runner_command'])
      elsif service_setup_data['machine'].key? 'start'
        @service_code.gsub!('[runner_command]', run_command)
      end
      if service_setup_data['machine'].key?('runner_path')
        @service_code.gsub!('[runner_path]', service_setup_data['machine']['runner_path'])
      else
        @service_code.gsub!('[runner_path]', '')
      end
      environment_variables.split(' ').each do |value|
        @configuration_file_content += "#{value}\n"
      end
      if !vault_data.nil? && vault_data != ''
        vault_data.split(' ').each do |value|
          @configuration_file_content += "#{value}\n"
        end
      end
      build_number = if service_setup_data.key?(:build_number)
                       service_setup_data[:build_number]
                     else
                       1
                     end
      @configuration_file_content += "BUILD_NUMBER=#{service_setup_data[:build_number]}\n"
    end
    @service_code.gsub!('[repo]', service_setup_data['deployment']['service_name'])
  end

  def install_service(destination_machine)
    case @service_type
    when 'systemd'
      create_systemd_service(destination_machine)
    when 'upstart'
      create_upstart_service(destination_machine)
    end
  end

  private

  def generate_systemd_service_code
    @service_code = "
      [Unit]
      Description=betterez service

      [Service]
      EnvironmentFile=/home/bz-app/[repo].env
      WorkingDirectory=/home/bz-app/[repo]/
      ExecStart=[runner_path] [runner_command]
      User=bz-app
      Restart=always

      [Install]
      WantedBy=multi-user.target
      "
  end

  def generate_upstart_service_code(run_command)
    @service_code = "
        ######### generate at #{Helpers.create_time_date_string} ##########
        start on runlevel [2345]
        stop on runlevel [!2345]
        script
        chdir /home/bz-app/[repo]/
        exec sudo -H -u bz-app bash -c '[vault_data] [environment_variables] BUILD_NUMBER=$(cat /home/bz-app/build_number.txt) #{run_command}'
        end script
        respawn
        ######################
        "
  end

  def create_upstart_service(destination_machine)
    destination_machine.upload_data_to_file @service_code, "/home/ubuntu/#{@service_setup_data['deployment']['service_name']}.conf"
    destination_machine.run_ssh_command "sudo service #{@service_setup_data['deployment']['service_name']} stop"
    destination_machine.run_ssh_command("sudo cp /home/ubuntu/#{@service_setup_data['deployment']['service_name']}.conf #{@service_file_location}")
    destination_machine.run_ssh_command "sudo service #{@service_setup_data['deployment']['service_name']} start"
  end

  def create_systemd_service(destination_machine)
    destination_machine.run_ssh_command "sudo systemctl stop #{@service_setup_data['deployment']['service_name']}.service"
    destination_machine.upload_data_to_file @service_code, "/home/ubuntu/#{@service_setup_data['deployment']['service_name']}.service"
    destination_machine.run_ssh_command("sudo mv /home/ubuntu/#{@service_setup_data['deployment']['service_name']}.service #{@service_file_location}")
    destination_machine.upload_data_to_file @configuration_file_content, "/home/ubuntu/#{@service_setup_data['deployment']['service_name']}.env"
    destination_machine.run_ssh_command("sudo mv /home/ubuntu/#{@service_setup_data['deployment']['service_name']}.env #{@configuration_file_location}")
    destination_machine.run_ssh_command('sudo chown -R bz-app:bz-app /home/bz-app/')

    destination_machine.run_ssh_command 'sudo systemctl daemon-reload'
    destination_machine.run_ssh_command "sudo systemctl start #{@service_setup_data['deployment']['service_name']}.service"
    destination_machine.run_ssh_command "sudo systemctl enable #{@service_setup_data['deployment']['service_name']}.service"
  end
end
