#!/usr/bin/ruby

require_relative  "betterez/ELBClient"
require 'optparse'
options = {:instance_secure_port => 80,instance_port: 80}
OptionParser.new do |opts|
  opts.banner = "usage: elb-creatot.rb [options]"
  opts.on("--internal","create an internal elb") do |argument|
    options[:internal]=true
  end  
  opts.on("--secure","create a secure elb") do |argument|
    options[:secure]=true
  end  
  opts.on("--instance-secure-port PORT",Integer,"instance port to forward to the 443 ssl port") do |argument|
    options[:instance_secure_port]=argument
  end
  opts.on("--instance-port PORT",Integer,"instance port to forward to the 80 http port") do |argument|
    options[:instance_port]=argument
  end
  opts.on("--elb-name NAME",String,"the elb name") do |argument|
    options[:elb_name]=argument
  end
end.parse!
raise OptionParser::MissingArgument if options[:elb_name].nil?
client=ELBClient.new
resp=client.create_elb(options)
print "New elb created.\r\nDNS:#{resp}\r\n"