require_relative('Helpers')

class ConfigurationData
  attr_accessor(:tasks,:clusterName,:filters)
  ECS="ecs_clusters"
  EC2="ec2_clusters"  
  def initialize(tasks,cluster,type)
    if cluster.class == "String"  then
      clusterName=cluster
    else
      clusterName=cluster.to_s
    end
    servers=Helpers.loadJSONData("settings/settings.json")
    if servers[type] == nil
      raise ArgumentError.new("can't find this type")
    end
    if servers[type][clusterName] == nil
      raise ArgumentError.new("can't find this cluster:#{clusterName}")
    end
    @data={:tasks=>tasks,:lb=>servers[type][clusterName]}
    @filters=[]
  end
  def getConfigurationData
    @data[:tasks].each do |task|
      if @filters.include? task[:taskDescriptionArn] then
        task[:filtered]=true
      else
        task[:filtered]=false
      end
    end
    @data
  end
end
