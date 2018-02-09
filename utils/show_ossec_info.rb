require_relative '../betterez/OssecManager'
#code=OssecManager.set_authentication_info "sandbox","bosszerez","JachnunNadal"
#puts "got #{code} updating ossec values."
environments=["staging","sandbox","production"]
environments.each do |environment|
  manger=OssecManager.new environment
  puts "auth info for #{environment}: #{manger.username}/#{manger.password}"
end
