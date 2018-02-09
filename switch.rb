#!/usr/bin/ruby
require_relative "betterez/Switcher"
require_relative "betterez/Notifire"

## Switches target machine from elb1 to elb2. can be use to switch one machine to multiple elbs

if(ARGV.length!=3) then
  print "usage is switch [command] source target1,target2...\r\n"
  exit(1)
end

switcher=Switcher.new(ARGV[1],ARGV[2].split(","))

if ARGV[0]=="list" then
  point=1
  print "listing elbs:\r\n"
  switcher.listAll.each do |elb|
    print "#{point}.#{elb}\r\n"
    point+=1
  end
elsif ARGV[0]=="check" then
  result,reason=switcher.checkElbInstances()
  if(result==true)then
    print "everything is ready to go\r\n"
  else
    print "#{reason}\r\n"
  end
elsif ARGV[0]=="switch" then
  print "switch servers..."
  notifire=Notifire.new
  switcher.notifire=notifire
  result,reason=switcher.switch()
  if(!result)
    print "failed #{reason}"
  else
    print "switch ok!"
  end
else
  print "nothing to do.\r\n"
end
print "\r\n"
code=0
if(!result)then
  code=1
end
exit(code)
