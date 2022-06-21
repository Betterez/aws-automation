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
    @users_policy_data={}
    # number of days after which key will consider not secure
    @days_to_validate = 90
    @days_to_clear_deletion = 10
    get_all_aws_keys
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

  ## is_key_ses_key - checks if this key is an ses key, which means that an ses code has to be created
  # key_id-+string+ the aws key id
  # return boolean and and error code. the error code will be nil if none occurred (true,nil)
  def is_key_ses_key(key_id)
    get_all_aws_keys
    client=Helpers.create_aws_iam_client
    return false,"Can't find this key id!"  if @keys_data_index[key_id].nil?
    key_data=@keys_data_index[key_id]
    return nil,"no user name found" if key_data[:username].nil?
    return true if (key_data[:ses_info]==true)
    if key_data[:ses_info].nil?
      resp=client.list_groups_for_user({
        user_name: key_data[:username]
      })
      @users_policy_data[key_data[:username]]={} if @users_policy_data[key_data[:username]].nil?
      user_policy_data=@users_policy_data[key_data[:username]]
      user_policy_data[:groups]=[] if user_policy_data[:groups].nil?
      resp.groups.each do |group_info|
        user_policy_data[:groups].push(group_info)
      end
      user_policy_data[:policies]=[] if user_policy_data[:policies].nil?
      user_policy_data[:groups].each do |selected_user_group|
        resp=client.list_group_policies({
          group_name: selected_user_group[:group_name]
          })
        user_policy_data[:policies].concat(resp.policy_names)
      end
      # load aws build in policies for that user
      user_policy_data[:groups].each do |selected_user_group|
        resp=client.list_attached_group_policies({
          group_name: selected_user_group[:group_name]
          })
        resp.attached_policies.each do |attach_policy|
          user_policy_data[:policies].push(attach_policy.policy_name)
        end
      end
      user_policy_data[:policies].each do |policy|
        puts "checking #{policy}"
        if policy.downcase.include?("ses")
          key_data[:ses_info]=true
          return true
        end
      end
    end
    return false
  end

  ## calculate_ses_password - calculate ses password from an aws key
  # key_secret - +string+
  # returns ses secret +string+
  def calculate_ses_password(key_secret)
    message = "SendRawEmail"
    versionInBytes = "\x02"
    signatureInBytes = OpenSSL::HMAC.digest('sha256', key_secret, message)
    signatureAndVer = versionInBytes + signatureInBytes
    smtpPassword = Base64.encode64(signatureAndVer)
    return smtpPassword.to_s.strip
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
  # vault_driver - +VaultDriver+ that is already configured to the correct environment
  # _secrets_manager - +SecretsManager+ that is already configured to the correct environment
  def check_security_for_service(_service_name, _vault_driver, _secrets_manager)
    get_all_aws_keys
    is_ses_key=false
    service_security_info=nil
    code=nil

    if _secrets_manager != nil
      puts "loading security info for repo from secrets manager"
      _secrets_manager.repository = _service_name
      service_security_info, code = _secrets_manager.get_secrets_hash
      puts "security info tried to be loaded from secrets manager"
    else
      throw "can't proceed with a nil driver" if _vault_driver.nil?
      throw "can't proceed with a offline driver" if !_vault_driver.get_vault_status
      #get the keys
      puts "loading security info for repo from vault"
      service_security_info, code = get_service_info_from_vault_driver(_vault_driver, _service_name)
      puts "security info tried to be loaded from vault"
    end

    return code if code > 399
    return nil,nil if (!service_security_info.key?(AWS_SERVICE_KEY))
    puts "looking for #{service_security_info[AWS_SERVICE_KEY]}(#{service_security_info[AWS_SERVICE_KEY].class}) in the keys directory"
    selected_key_information=@keys_data_index[service_security_info[AWS_SERVICE_KEY]]
    return nil,"can't find data entry for this key: #{service_security_info[AWS_SERVICE_KEY]}" if selected_key_information.nil?
    is_ses_key,error=is_key_ses_key(service_security_info[AWS_SERVICE_KEY])
    throw "Can't check ses key - #{error}" if (!error.nil?)
    puts "service is not using ses " if is_ses_key==false
    puts "This is a ses service" if is_ses_key==true
    username=selected_key_information[:username]
    all_user_keys_info=@all_users_keys[username]
    updated_key_info,error=update_user_iam_keys({username=>all_user_keys_info})
    puts "error: #{error}" if error!=nil
    puts "nothing to update" if updated_key_info.nil?
    if error.nil? && !updated_key_info.nil?
      puts "new key created:#{updated_key_info.access_key.access_key_id}"
      update_hash={AWS_SERVICE_KEY=>updated_key_info.access_key.access_key_id,"aws_service_secret"=>updated_key_info.access_key.secret_access_key}
      #if is_ses_key
      #  puts "this service is using ses"
      #  update_hash["email_client_username"]=updated_key_info.access_key.access_key_id
      #  update_hash["email_client_password"]=calculate_ses_password(updated_key_info.access_key.secret_access_key)
      #end
      if _secrets_manager != nil
        code = _secrets_manager.set_secret_value(update_hash, true)
      else
        code=_vault_driver.put_json_for_repo(_service_name,
          update_hash,
          true,)        
      end
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
