#!/usr/bin/ruby
require_relative "Helpers"

class Tagger
  def initialize()
    @tags=[]
  end
  def createClient
    Aws.config[:ssl_ca_bundle] ="cacert.pem"
    client = Aws::EC2::Client.new(region: "us-east-1",credentials: Helpers.create_aws_authentication_token())
  end
  def listInstancesByTag (tags)
    client=createClient
    instances=[]
    resp=client.describe_instances(filters: [
      {name: "tag:Environment", values: ["prod"]}
      ])
    resp.reservations.each do |reservation|
      reservation.instances.each do |instance|
        instance_data={:private_ip => instance.network_interfaces[0].private_ip_address}
        instance_data[:instance_id] = instance.instance_id
        instance.tags.each do |tag|
          instance_data[tag.key] = tag.value;
        end
        instances.push(instance_data);
      end
    end
    return instances
  end 
end