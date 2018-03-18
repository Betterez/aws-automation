require 'aws-sdk'
require_relative 'Helpers'
class SecurityChecker
  ERROR_NO_USAGE_DATA = 'error - no usage data'.freeze
  IAM_KEY_STATUS_INACTIVE = 'Inactive'.freeze
  IAM_KEY_STATUS_ACTIVE = 'Active'.freeze
  AWS_SERVICE_KEY = 'aws_service_key'.freeze
  attr_reader(:all_users)
  attr_reader(:all_users_keys)
  attr_reader(:keys_data_index)
  attr_accessor(:days_to_validate)
  attr_accessor(:days_to_clear_deletion)
  def initialize
    @keys_data_index = nil
    @all_users = nil
    @all_users_keys = nil
    # number of days after which key will consider not secure
    @days_to_validate = 90
    @days_to_clear_deletion = 10
  end

  ## checks if parameters contains any known services keys. currently supported mongo and aws
  # service_params - +string+ "key=value,key2=value2"
  def check_service_params(service_params)
    service_keys = []
    [{ name: :aws, key: 'AWS_SERVICE_KEY' }, { name: :mongo, key: 'MONGO_DB_USERNAME' }].each do |key_data|
      key_index = service_params.index(key_data[:key])
      next if key_index.nil?
      key_value = get_key_value_for_param(key_data[:key], service_params)
      throw 'no value for this key key' if key_value.nil?
      service_keys.push(key_name: key_data[:name], key_value: key_value)
    end
    service_keys
  end

  def get_service_info_from_vault_driver(vault_driver, service_name)
    data, code = vault_driver.get_json("secret/#{service_name}")
    return data, code if code < 399
    [nil, code]
  end

  ## return the key value for a key name
  # key_value - +string+ - the key name
  # service_params - +string+ service parameters "key=value,key2=value2"
  def get_key_value_for_param(key_value, service_params)
    return nil if key_value.nil?
    params_index = service_params.index(key_value)
    return nil if params_index.nil?
    params_index = service_params.index('=', params_index)
    return nil if params_index.nil?
    params_index += 1
    end_index = service_params.index(',', params_index)
    if end_index.nil?
      end_index = params_index
      return nil if end_index >= service_params.length
      end_index = service_params.length
    end
    service_params[params_index...end_index]
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
          usage: dateyfay(key_resp.access_key_last_used.last_used_date),
          status: key_metadata.status,
          created_date: dateyfay(key_metadata.create_date),
          username: username
        }
        @keys_data_index[key_data[:key_id]] = key_data
        if @all_users_keys[username].nil?
          @all_users_keys[username] = [key_data]
        else
          @all_users_keys[username].push key_data
        end
      end
    end
    @keys_data_index
  end

  def dateyfay(param)
    if param.nil?
      nil
    elsif param.class == Time
      DateTime.parse(param.to_s)
    elsif param.class == DateTime
      param
    end
  end

  ## check_key_validity - checks if this key is valid from a security point of view
  # key_info - +hash+ include key_name (:aws, :mongo) and key_value +string+
  # returns: valid or invalid and an error string if one happend. else the error string will be nil
  def check_key_validity(key_info)
    if key_info[:key_name] == :aws
      return 'error', "can't find this key" if @keys_data_index[key_info[:key_value].to_sym].nil?
      if (DateTime.now - @days_to_validate) > (@keys_data_index[key_info[:key_value].to_sym][:created_date])
        return 'invalid', nil
      else
        return 'valid', nil
      end
    else
      ['error', 'key unknown']
    end
  end

  ## update_user_iam_keys - removes an old iam key and creates a new one
  # user_info - +hash+ containg keys array {"username":[key_id:,usage:,status:,created_date:,username:],}
  # returns key response and and nil as error or nil and an error code
  def update_user_iam_keys(user_info)
    user_key = user_info.keys[0]
    can_create_access_key = false
    resp = error = nil
    if user_info[user_key].length == 2
      user_info[user_key].each do |user_key_info|
        break if can_create_access_key
        # old key, no usage -> delete
        if user_key_info[:usage].nil? && (DateTime.now - @days_to_validate > user_key_info[:created_date])
          delete_iam_access_key(user_key_info)
          can_create_access_key = true
        # valid key, no usage
        elsif user_key_info[:usage].nil? && (DateTime.now - @days_to_validate <= user_key_info[:created_date])
          next
        # old key, active, -> needs to be freezed
        elsif
          (user_key_info[:usage] < DateTime.now - @days_to_clear_deletion) &&
          (DateTime.now - @days_to_validate > user_key_info[:created_date]) &&
          (user_key_info[:status] == IAM_KEY_STATUS_ACTIVE)

          deactivate_iam_access_key(user_key_info)
        # old key, 2 freezing periods, and inactive
        elsif (user_key_info[:usage] < (DateTime.now - 2 * @days_to_clear_deletion)) &&
              (DateTime.now - @days_to_validate > user_key_info[:created_date]) &&
              (user_key_info[:status] == IAM_KEY_STATUS_INACTIVE)
          delete_iam_access_key(user_key_info)
          can_create_access_key = true
        end
      end
    else
      can_create_access_key = true
    end

    resp = create_aws_access_key_for_user(user_info.keys[0].to_s) if can_create_access_key
    [resp, error]
  end

  def update_iam_info_to_vault(vault_driver, access_key_response,_repository_name)
    params = { aws_service_key: access_key_response.access_key.access_key_id, aws_service_secret: access_key_response.access_key.secret_access_key }
    vault_driver.put_json_for_repo(_repository_name, params, true)
  end

  ## deactivates access key from aws.
  # user_key_info - +hash+ {key_id:"AKIA11111111111111111111",usage:nil,status:"Active",created_date:"2017-11-15 16:27:02 UTC",username:"user"}
  def deactivate_iam_access_key(user_key_info)
    iam_client = Helpers.create_aws_iam_client
    resp = iam_client.update_access_key(
      user_name: user_key_info[:username],
      access_key_id: user_key_info[:key_id],
      status: 'Inactive'
    )
  end

  ## deletes access key from aws.
  # user_key_info - +hash+ {key_id:"AKIA11111111111111111111",usage:nil,status:"Active",created_date:"2017-11-15 16:27:02 UTC",username:"user"}
  def delete_iam_access_key(user_key_info)
    iam_client = Helpers.create_aws_iam_client
    iam_client.delete_access_key(
      access_key_id: user_key_info[:key_id],
      user_name: user_key_info[:username]
    )
  end

  ## creates an aws key for this username
  def create_aws_access_key_for_user(username)
    iam_client = Helpers.create_aws_iam_client
    resp = iam_client.create_access_key(
      user_name: username
    )
    resp
  end

  ## aws_key_be_deleted - checks if this key is eligible  from a security point of view
  # key_info - +hash+ include key_name (:aws, :mongo) and key_value +string+
  # returns: valid or invalid and an error string if one happend. else the error string will be nil
  def aws_key_can_be_deleted(key_info)
    result, err = check_key_validity(key_info)
    return false unless err.nil?
    return false if @keys_data_index[key_info[:key_value].to_sym][:usage].nil?
    if (DateTime.now - @days_to_clear_deletion) > (@keys_data_index[key_info[:key_value].to_sym][:usage])
      return true
    end
    false
  end

  ## check_security_for_service -load the service info from vault and checks for
  # service_name -+string+  service needed inspection
  # vault_driver - +VaultDriver+ that is already configured to that environment
  def check_security_for_service(_service_name, _vault_driver)
    get_all_aws_keys
    throw "can't proceed with a nil driver" if _vault_driver.nil?
    throw "can't proceed with a offline driver" if !_vault_driver.get_vault_status
    #get the keys
    service_security_info, code = get_service_info_from_vault_driver(_vault_driver, _service_name)
    return code if code > 399
    return nil,nil if (!service_security_info.key?(AWS_SERVICE_KEY))
    puts "looking for #{service_security_info[AWS_SERVICE_KEY]} in the keys directory"
    key_info=@keys_data_index[service_security_info[AWS_SERVICE_KEY]]
    return nil,"can't find data entry for this key: #{service_security_info[AWS_SERVICE_KEY]}"
    username=key_info[:username]
    all_user_keys_info=@all_users_keys[username]
    updated_key_info,error=update_user_iam_keys({username=>all_user_keys_info})
    puts "error: #{error}" if error!=nil
    puts "nothing to update" if updated_key_info.nil?
    if error.nil? && !updated_key_info.nil?
      puts "new key created:#{updated_key_info.access_key.access_key_id}"
      code=_vault_driver.put_json_for_repo(_service_name,
        {AWS_SERVICE_KEY=>updated_key_info.access_key.access_key_id,"aws_service_secret"=>updated_key_info.access_key.secret_access_key},
        true,)
    end
    return code,nil
  end

  ## remove all keys for the current user create a new key and update vault.
  ## caution: only use in cases where the key was removed manually
  # _vault_driver -+VaultDriver+ class instance
  # _username -+string+ the aws username for that key
  # returns success code and an error. nil,error or code,nil on success
  def force_create_and_update_user_key(_vault_driver,_username,_repository_name)
    get_all_aws_keys
    return nil,"Can't find a key for this user: #{_username}" if !@all_users_keys.key?(_username)
    @all_users_keys[_username].each do |user_key_info|
      delete_iam_access_key(user_key_info)
    end
    resp = create_aws_access_key_for_user(_username)
    code,error=update_iam_info_to_vault(_vault_driver,resp,_repository_name)
    return code,error
  end

  ## for username / password pair, check to see if they are valid.
  # mongo_params - +hashmap+ {:username,:password}
  def check_mongo_parameters(mongo_params); end
end
