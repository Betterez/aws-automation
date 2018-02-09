require_relative "Helpers"
class AwsServicesLoader
  def createClient
    Aws.config[:ssl_ca_bundle] ="cacert.pem"
    elasticloadbalancing = Aws::EC2::Client.new(region: "us-east-1",credentials: Helpers.create_aws_authentication_token())
  end
  def getServiceInstances(service,environment)
    servers=[]
    resp=createClient().describe_instances({
      dry_run: false,
      #note: filters in the same filter are ORed, filter in separate filters are ANDed
      filters: [
        {
          name: "tag:Environment", values: [environment],          
        },
        {
          name: "tag:Type", values: [service],
        }
      ]
      })    
    resp.reservations.each do |page|
      page.instances.each do |instance|
        server={}
        if (instance.network_interfaces[0])
          server["ip"]=instance.network_interfaces[0].private_ip_addresses[0].private_ip_address;
        end
          server["id"]=instance.instance_id
        instance.tags.each do |tag|
          if(tag["key"]=="Name")
            server["Name"]=tag["value"]
          end
        end
        servers.push(server)
      end
    end
    return servers
  end
  def getLoadBalancers(environment,type)
    resp=createClient().describe_instances({
      dry_run: false,
      #note: filters in the same filter are ORed, filter in separate filters are ANDed
      filters: [
        {
          name: "tag:Environment", values: [environment],          
        },
        {
          name: "tag:Type", values: type,
        }
      ]      
      })
      
  end
end