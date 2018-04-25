require_relative 'AwsInstance'
module Packer
  def self.load_images_data(packer_images_parameters)
    packer_images_data={}
    images_folder=packer_images_parameters[:packer_path]+"/image_files/*.json"
    Dir[images_folder].each do |filename|
      Helpers.log "checking #{filename}..."
      filedata = Helpers.loadJSONData filename
      if filedata.nil?
        Helpers.log "failed to load #{filename}"
        next
      end
      ami_tags = filedata['builders'][0]['tags']
      ami_type = ami_tags['Type']
      ami_name= ami_tags['Name']
      expected_image_type = packer_images_parameters[:packer_path] + '/image_files/' + ami_type + '.json'
      expected_image_name = packer_images_parameters[:packer_path] + '/image_files/' + ami_name + '.json'
      if expected_image_type != filename || expected_image_name!=filename
        throw "#{filename}: type #{ami_type} doesn't match file name, (expecting #{expected_image_type})."
      else
        packer_images_data[ami_type] = filedata
        packer_images_data[ami_type]['filename'] = filename
        Helpers.log "#{filename} loaded!"
      end
    end
    packer_images_data
  end

  def self.load_aws_images_data(images_data,account_id)
    aws_ec2_client = Helpers.create_aws_ec2_client
    current_aws_images = []
    resp = aws_ec2_client.describe_images(dry_run: false,
                                          filters: [
                                            {
                                              name: 'state', values: ['available']
                                            }
                                          ],
                                          #owners: [images_data[:aws_account_id]])
                                          owners: [account_id])
    Helpers.log 'Done, sorting'
    resp.images.each do |image|
      current_aws_images.push(image)
    end
    current_aws_images.sort! { |a, b| a.creation_date <=> b.creation_date }
    current_aws_images.each do |image|
      image_version = nil
      image_type = nil
      image.tags.each do |tag|
        image_version = tag.value.to_i if tag.key == 'Version'
        image_type = tag.value if tag.key == 'Type'
      end
      next if images_data[image_type].nil?
      images_data[image_type]['aws_version'] = image_version if !image_version.nil? && !image_type.nil?
      image_version = nil
      image_type = nil
    end
  end

  def self.create_packer_file_data(packer_images_parameters,packer_images_data)
    Helpers.log packer_images_parameters
    packer_file_data=""
    authentication = Helpers.load_json_data_to_hash('settings/authentication.json')
    packer_images_data.each do |image_type|
      if image_type[1]['aws_version'].nil?
        Helpers.log "need to build #{image_type[1]['builders'][0]['tags']['Type']} (new image)"
      elsif  image_type[1]['builders'][0]['tags']['Version'].to_i > image_type[1]['aws_version']
        Helpers.log "need to build #{image_type[1]['builders'][0]['tags']['Type']} (old version)"
      else
        next
      end
      aws_source_ami_id=packer_images_parameters[:base_ami_id]
      #loads image type from script file instead of parameter
      if image_type[1].has_key?"variables" and image_type[1]["variables"].has_key?"base_ami_name" then
        aws_source_ami_id=AwsInstance.get_ami_id(image_type[1]["variables"]["base_ami_name"])
      end
      packer_command = "cd #{packer_images_parameters[:packer_path]} && " \
                       "packer build -var 'access_key=#{authentication[:access_key_id]}' " \
                       "-var 'secret_key=#{authentication[:secret_access_key]}' " \
                       "-var 'source_ami=#{aws_source_ami_id}' " \
                       "#{image_type[1]['filename']}"
      packer_file_data += packer_command
      packer_file_data += "\n"
    end
    packer_file_data
  end

  def self.create_packer_build_file(build_file_data)
    packer_file_name="transient/packer.sh"
    begin
      File.delete packer_file_name
    rescue
    end
    packer_file = File.open(packer_file_name, 'w')
    if build_file_data != ''
      packer_file.write(build_file_data)
      packer_file.close
      return true
    else
      return false
    end
  end

  def self.setup
    transient_dir = 'transient'
    file_name = 'packer.sh'
    Dir.mkdir(transient_dir) unless Dir.exist?(transient_dir)
    File.delete(transient_dir + '/' + file_name) if File.exist?(transient_dir + '/' + file_name)
  end
end
