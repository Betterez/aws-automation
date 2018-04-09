require_relative 'Helpers'
require_relative 'Notifire'
require_relative 'VaultDriver'

class Syslogger
  def initialize(aws_instance,vault_driver,service_name)
    @aws_instance=aws_instance
    @vault_driver=vault_driver
    @service_name=service_name
  end
  def check_record_exists
    result=@aws_instance.run_ssh_command("cat /etc/rsyslog.conf |grep logentries")
    return false if result.strip==""
    return true
  end
  ##  add_record_to_rsyslog - adding a record to syslog
  # return boolean result add (yes/no) and an error code
  def add_record_to_rsyslog
    data, code=@vault_driver.get_json("secret/#{@service_name}")
    if code>399
      return false,code
    end
    return false ,"record already exists!" if check_record_exists
    return false,"no logentries token found" if !data.has_key?("logentries_token")
    footer="'$template Logentries,\"#{data['logentries_token']} %HOSTNAME% %syslogtag%%msg%\"\n *.* @@data.logentries.com:80;Logentries'"
    result=@aws_instance.run_ssh_command("echo #{footer} | sudo tee --append /etc/rsyslog.conf")
    if check_record_exists
      @aws_instance.run_ssh_command("sudo service rsyslog restart")
    else
      return false,"failed to setup command"
    end
    @aws_instance.run_ssh_command("logger -t test Testing logger command")
    return true,nil
  end
end
