class AwsInstanceMock
  def run_ssh_command command
    puts "running command #{command}"
  end
  def upload_data_to_file data,path
    puts "uploading to #{path}:\n"
    puts data
    puts "****"
  end
end
