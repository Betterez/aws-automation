require_relative '../../betterez/VaultDriver'
class AwsInstanceMock
  attr_reader(:status)
  def initialize
    @instance_id=VaultDriver.generate_uid
    @status="ready"
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
    @status="terminated"
  end
end
