require 'aws-sdk'
require_relative 'Helpers'
class SecurityChecker
  attr_reader(:all_users)
  attr_reader(:all_users_keys)
  attr_reader(:keys_data_index)
  def initialize
    @keys_data_index = nil
    @all_users = nil
    @all_users_keys = nil
  end

  ## checks if parameters contains any known services keys. currently supported mongo and aws
  # service_params - +string+ "key=value,key2=value2"
  def check_service_params(service_params)
    service_keys = []
    [{ name: :aws, key: 'AWS_SERVICE_KEY' }, { name: :mongo, key: 'MONGO_DB_USERNAME' }].each do |key_data|
      key_index=service_params.index(key_data[:key])
      if !key_index.nil?
        key_value=get_key_value_for_param(key_data[:key],service_params)
        throw "no value for this key #{:key}" if key_value.nil?
        service_keys.push({key_name: key_data[:name],key_value: key_value})
      end
    end
    service_keys
  end

  ## return the key value for a key name
  # key_value - +string+ - the key name
  # service_params - +string+ service parameters "key=value,key2=value2"
  def get_key_value_for_param(key_value,service_params)
    return nil if key_value.nil?
    params_index=service_params.index(key_value)
    return nil if params_index.nil?
    params_index=service_params.index("=",params_index)
    return nil if params_index.nil?
    params_index+=1
    end_index=service_params.index(",",params_index)
    if end_index.nil?
      end_index=params_index
      return nil if end_index>=service_params.length
      end_index=service_params.length
    end
    return service_params[params_index...end_index]
  end

  ## for key / secret pair, check to see if they are valid. and how long since they have been used
  # aws_params - +hashmap+ {:key,:secret}

  ## gets all aws users and their keys if exists
  def get_all_aws_keys(refresh = false)
    return if !@all_users_keys.nil? && !refresh

    @all_users = []
    @all_users_keys = {}
    @keys_data_index = {}
    iam_client = Helpers.create_aws_iam_client
    resp = iam_client.list_users({})
    resp.users.each do |current_user|
      @all_users.push(current_user.user_name)
    end
    @all_users.each do |username|
      resp = iam_client.list_access_keys(
        user_name: username
      )
      resp.access_key_metadata.each do |key_metadata|
        # puts "#{key_metadata.user_name} - #{key_metadata.access_key_id}\r\n\r\n"
        next if key_metadata.access_key_id.nil?
        key_resp = iam_client.get_access_key_last_used(
          access_key_id: key_metadata.access_key_id
        )
        key_data = {
          key_id: key_metadata.access_key_id,
          usage: key_resp.access_key_last_used.last_used_date,
          status: key_metadata.status,
          created_date: key_metadata.create_date,
          username: username,
        }
        @keys_data_index[key_data[:key_id]]=key_data
        if @all_users_keys[username].nil?
          @all_users_keys[username] = [key_data]
        else
          @all_users_keys[username].push (key_data)
        end
      end
    end
    @keys_data_index
  end

  ## check_key_validity - checks if this key is valid from a security point of view
  # key_info - +hash+ include key_name (:aws, :mongo) and key_value +string+
  def check_key_validity(key_info)
    if(key_info[:key_name]==:aws) then
      throw "can't find this key " if @keys_data_index[:key_value].nil?

    end
  end

  ## for username / password pair, check to see if they are valid.
  # mongo_params - +hashmap+ {:username,:password}
  def check_mongo_parameters(mongo_params); end
end
