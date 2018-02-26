require 'aws-sdk'
require_relative "Helpers"
class SecurityChecker
  def initialize
    @all_users=nil
    @all_users_keys=nil
  end

  ## checks if parameters contains any known services.
  # params - +string+ "key=value,key2=value2"
  def check_params(params)
    available_keys = []
    [{ name: :aws, key: 'AWS_SERVICE_KEY' }, { name: :mongo, key: 'MONGO_DB_USERNAME' }].each do |key_data|
      available_keys.push(key_data[:name]) unless params.index(key_data[:key]).nil?
    end
    available_keys
  end

  ## for key / secret pair, check to see if they are valid. and how long since they have been used
  # aws_params - +hashmap+ {:key,:secret}


## gets all aws users and their keys if exists
  def get_all_aws_keys(refresh=false)
    return @all_users_keys if (!@all_users_keys.nil?&&!refresh)

    @all_users=[]
    @all_users_keys={}
    iam_client=Helpers.create_aws_iam_client
    resp=iam_client.list_users({})
    resp.users.each do |current_user|
      @all_users.push( current_user.user_name)
    end
    @all_users.each do |username|
      resp=iam_client.list_access_keys({
        user_name: username,
        })
      resp.access_key_metadata.each do |key_metadata|
        #puts "#{key_metadata.user_name} - #{key_metadata.access_key_id}\r\n\r\n"
        if !(key_metadata.access_key_id.nil?)
          key_resp=iam_client.get_access_key_last_used({
            access_key_id: key_metadata.access_key_id
            })
          if @all_users_keys[username].nil?
            @all_users_keys[username]=[{
              key_id: key_metadata.access_key_id,
              usage: key_resp.access_key_last_used.last_used_date,
              status: key_metadata.status,
              created_date: key_metadata.create_date,
              }]
          else
            @all_users_keys[username].push ({
              key_id: key_metadata.access_key_id,
              usage: key_resp.access_key_last_used.last_used_date,
              status: key_metadata.status,
              created_date: key_metadata.create_date,
              })
          end
        end
      end
    end
    @all_users_keys
  end

## gets the last usage of an access key2
# access_key - +string+ the access key id AKIXXXXXXXXXXXXXXXX
# returns - time.
  def get_aws_access_key_info(access_key)
    iam_client=Helpers.create_aws_iam_client
    resp=iam_client.get_access_key_last_used({
      access_key_id: access_key
      })
    resp
  end

  ## for username / password pair, check to see if they are valid.
  # mongo_params - +hashmap+ {:username,:password}
  def check_mongo_parameters(mongo_params)

  end


end
