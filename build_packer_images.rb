#!/usr/bin/ruby

require 'open3'
require 'optparse'
require_relative 'betterez/AwsInstance'
require_relative 'betterez/Packer'
require_relative 'betterez/Helpers'

def main
  packer_images_parameters = { create_image: true ,base_ami_id: nil}
  aws_account_data=Helpers.loadJSONData("settings/aws-auth.json")
  throw "can't load account data" if aws_account_data.nil?
  packer_images_parameters[:aws_account_id]=aws_account_data["aws"]["account_id"]
  OptionParser.new do |opts|
    opts.banner = "usage: #{__FILE__} [options]"
    opts.on('--pp PACKER_PATH', 'where packer files are located.') do |argument|
      packer_images_parameters[:packer_path] = argument
    end
    opts.on('--base_type BASE_TYPE', 'the base type of the ami to be used as source.') do |argument|
      packer_images_parameters[:base_type] = argument
    end
    opts.on('--image_id IMAGE_ID', 'the image id (no need for a base type).') do |argument|
      packer_images_parameters[:base_ami_id] = argument
      packer_images_parameters[:use_image_id] = true
    end
  end.parse!
  raise OptionParser::MissingArgument if packer_images_parameters[:packer_path].nil? || packer_images_parameters[:packer_path] == ''
  raise OptionParser::MissingArgument if (packer_images_parameters[:base_type].nil? || packer_images_parameters[:base_type] == '') && packer_images_parameters[:base_ami_id].nil?
  Packer.setup
   if packer_images_parameters[:base_ami_id].nil?
     packer_images_parameters[:base_ami_id]= AwsInstance.get_ami_id(packer_images_parameters[:base_type])
     Helpers.log "loading image id for #{packer_images_parameters[:base_type]} - #{packer_images_parameters[:base_ami_id]}"
     if packer_images_parameters[:base_ami_id]==nil || packer_images_parameters[:base_ami_id]==""
       throw "can't find packer image id! #{packer_images_parameters[:base_type]}"
     end
   end
  packer_images_data = Packer.load_images_data packer_images_parameters
  Helpers.log 'loading aws images data'
  #packer_images_data[:aws_account_id]=aws_account_data["aws"]["account_id"]    
  Packer.load_aws_images_data(packer_images_data,aws_account_data["aws"]["account_id"])
  packer_file_data = Packer.create_packer_file_data(packer_images_parameters,packer_images_data)
  Packer.create_packer_build_file packer_file_data
end
main
