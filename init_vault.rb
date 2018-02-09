require 'optparse'
vault_settings={}
OptionParser.new do |opts|
  opts.banner = 'usage: init_vault.rb [options]'
  opts.on('--token TOKEN', 'root token') do |argument|
    vault_settings[:token] = argument
  end
end.parse!

fail OptionParser::MissingArgument if vault_settings[:token]==nil
