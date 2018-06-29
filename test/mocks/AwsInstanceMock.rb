require_relative '../../betterez/VaultDriver'
class AwsInstanceMock
  def initialize
    @instance_id=VaultDriver.generate_uid
    puts "creating new mock instance #{@instance_id}"
  end
  def run_ssh_command command
    puts "running command #{command}"
  end
  def upload_data_to_file data,path
    puts "uploading to #{path}:\n"
    puts data
    puts "****"
  end
  def get_aws_id
    @instance_id
  end
  def get_tag_by_name(name)
    return "tag-#{name}"
  end
  def terminate_instance
    puts "terminating instance #{@instance_id}"
  end
end
