require 'net/http'
require 'json'
require_relative('Helpers')
class VaultDriver
    attr_reader(:locked)
    attr_reader(:authorized)
    attr_reader(:online)
    attr_reader(:url)
    attr_reader(:all_repos_path)
    attr_accessor(:token)

    # New vault driver.
    # * +address+ - +string+ The server address
    # * +port+ - +Integer+ The server's port
    # * +token+ - +string+ The user tokem
    def initialize(address, port, token)
      throw "bad vault address" if nil==address
      throw "bad vault port" if nil==port
      throw "bad vault token" if nil==token
        @url = "http://#{address}:#{port}/v1/"
        @token = token
        @all_repos_path = 'secret/all_repos_path_storage_hash'
        @online = false
    end

    # Create a new vault driver from a secret file
    # * +filename+ - +string+ the full file path
    # * +environment+ - +string+ the server environment
    def self.from_secrets_file(environment,filename=nil)
      filename = "settings/secrets.json" if filename==nil
      throw "secret file not exist" if !File.exists? filename
      secrets=Helpers.load_json_data_to_hash filename
      throw "error loading file data" if secrets==nil
      throw "vault - Can't find this environment , #{environment}" if !secrets.has_key?environment.to_sym
      vault_data=secrets[environment.to_sym][:vault]
      return VaultDriver.new vault_data[:address],vault_data[:port],vault_data[:token]
    end
    # generage uiid string for vault. static.
    #
    # returns +string+ the created uiid
    def self.generate_uid
        source = 'ABCDEF1234567890'
        result = ''
        cycle = [8, 4, 4, 4, 12]
        seed = Random.new
        cycle.each_with_index do |run, index|
            for _ in 1..run
                result += source[seed.rand(source.length)]
            end
            result += '-' if index < cycle.length - 1
        end
        result
    end

    # Calculate the vault status.
    # Call this function before storing or retrieving values from vault, only need to call it once.
    #
    # returns: return value is not important
    def get_vault_status
        str = Helpers.create_random_string(50)
        @locked = false
        @authorized = true
        @online = true
        _, code = get_json(str)
        if code == 503
            @locked = true
        elsif code == 502 || code == 504
            @online = false
        elsif code < 300 || code == 404
            @locked = false
        elsif code == 401 || code == 403
            @authorized = false
        end
        @online && !@locked && @authorized
    end

    def get_vault_info
      {"locked"=>@locked,"url"=>@url,"authorized":@authorized,"online":@online,"token"=>@token}
    end

    # Gets system vaiables string for a named service.
    #
    # returns +string+ the found variables. empty string if none were found.
    def get_system_variables_for_service(service_name)
        vault_data = ''
        data, code = get_json("secret/#{service_name}")
        return '' if code > 399
        data.keys.each do |key|
            if !data[key].nil? && data[key].strip != ''
                vault_data += key.upcase + '=' + data[key] + ' '
            end
        end
        vault_data
    end

    # Unlock the vault.
    # * +keys+ - +strings+ +Array+  the keys to unlock the vault.
    # returns +integer+ the http return code.
    def unlock_vault(keys)
        throw 'keys must be an array' if keys.class != Array
        res = nil
        uri = URI(@url + 'sys/unseal')
        req = Net::HTTP::Put.new(uri)
        data = {}
        keys.each do |key|
            data['key'] = key
            res = Net::HTTP.start(uri.hostname, uri.port) do |http|
                req.body = data.to_json
                http.request(req)
            end
        end
        get_vault_status
        res.code.to_i
    end

    # get json data for selected path.
    # * +path+ - +string+, have to be in the format of secret/mypath
    # returns +hash+ and an +integer+ code.
    def get_json(path)
        throw "Can't use a locked vault" if @locked == true
        throw 'bad token value' if @authorized == false
        uri = URI(@url + path)
        req = Net::HTTP::Get.new(uri)
        req['X-Vault-Token'] = @token
        begin
            res = Net::HTTP.start(uri.hostname, uri.port) do |http|
                http.request(req)
            end
            data = nil
            if res.code.to_i < 300
                payload = JSON.parse(res.body)
                data = payload['data']
            end
        rescue => _
            return nil, 502
        end
        return data, res.code.to_i
    end

    # stores json data in a selected path
    # *  +path+ - +string+ need to include the secret/ prefix (e.g secret/mypath)
    # *  +json_data+ - +hash+
    def put_json_in_path(path, json_data)
        res = nil
        uri = URI(@url + path)
        req = Net::HTTP::Post.new(uri)
        req['X-Vault-Token'] = @token
        res = Net::HTTP.start(uri.hostname, uri.port) do |http|
            req.body = if json_data.class == Hash
                           json_data.to_json
                       else
                           json_data
                       end
            http.request(req)
        end
        res.code.to_i
    end

    # puts up json data for a repo. stores the repo in the list, for other usage
    # *  +repo+ - +string+
    # *  +json_data+ - +hash+
    # *  +append+ - +boolean+  - don't create new json, just update the existing values, keep all the others.
    # return +integer+ - the http return code
    def put_json_for_repo(repo, json_data, append)
        throw "Can't use a locked vault" if @locked == true
        throw 'bad token value' if @authorized == false
        path = "secret/#{repo}"
        data, code = get_json(@all_repos_path)
        return code if code > 399 && code != 404
        if code == 404
            data = { 'repos' => { repo => 1 } }
        else
            data['repos'][repo] = 1
        end
        code = put_json_in_path(@all_repos_path, data)
        return code if code > 399
        if append
            current_dataset, code = get_json(path)
            if code > 399 && code != 404
                return code
            elsif code == 404
                current_dataset = {}
            end
            json_data.keys.each do |key|
                current_dataset[key] = json_data[key]
            end
            code = put_json_in_path(path, current_dataset)
        else
            code = put_json_in_path(path, json_data)
        end
    end

    def delete_value(repo,key_name)
      throw "Can't use a locked vault" if @locked == true
      throw 'bad token value' if @authorized == false
      path = "secret/#{repo}"
      code = ensure_repo_listing repo
      return code if code > 399
      current_dataset, code = get_json(path)
      if code > 399 && code != 404
          return code
      elsif code == 404
          return 200
      end
      updated_dataset={}
      current_dataset.keys.each do |key|
        next if key==key_name
        updated_dataset[key]=current_dataset[key]
      end
      code=put_json_for_repo(repo,updated_dataset,false)
    end

    ## ensures that a repo is listed within all repos hash
    def ensure_repo_listing (repo)
      data, code = get_json(@all_repos_path)
      return code if code > 399 && code != 404
      # putting repo in the list
      if code == 404
          data = { 'repos' => { repo => 1 } }
      else
          data['repos'][repo] = 1
      end
      code = put_json_in_path(@all_repos_path, data)
    end

    ##lists all registered repos
    def list_all_registered_repos
      data, code = get_json(@all_repos_path)
      return data,code
    end

    ## puts json for all the listed repos
    def put_json_for_all_repos(json_data, append)
        throw "Can't use a locked vault" if @locked == true
        throw 'bad token value' if @authorized == false
        data, code = get_json(@all_repos_path)
        return code if code == 404
        results = {}
        data['repos'].keys.each do |key|
            code = put_json_for_repo(key, json_data, append)
            results[key] = code
        end
        results
    end

    # (1) initialization. create an application name.
    #
    # returns +integer+ the creation http code
    def init_application(application_name)
        if application_name.nil? || application_name == ''
            throw 'Bad application name'
        end
        res = nil
        applicaiton_init_uri = URI(@url + "sys/auth/#{application_name}")
        req = Net::HTTP::Post.new(applicaiton_init_uri)
        req['X-Vault-Token'] = @token
        res = Net::HTTP.start(applicaiton_init_uri.hostname, applicaiton_init_uri.port) do |http|
            req.body = { 'type' => 'app-id' }.to_json
            http.request(req)
        end
        res.code.to_i
    end

    # (2) initialization. create an application id.
    #
    # returns: +string+ applicaiton_id, +integer+ the creation http code
    def create_application_id(application_name)
        applicaiton_id = VaultDriver.generate_uid
        applicaiton_create_uri = URI(@url + "auth/#{application_name}/map/app-id/#{applicaiton_id}")
        req = Net::HTTP::Post.new(applicaiton_create_uri)
        req['X-Vault-Token'] = @token
        res = Net::HTTP.start(applicaiton_create_uri.hostname, applicaiton_create_uri.port) do |http|
            req.body = { 'value' => 'root', 'display_name' => application_name.to_s }.to_json
            http.request(req)
        end
        [applicaiton_id, res.code.to_i]
    end

    # (3) initialization. create a user under an existing application.
    # * +application_name+ - +string+
    # * +application_id+ - +string+
    # returns: user_id - +string+ and code - +integer+ the creation http code
    def create_user(application_name, application_id)
        res = nil
        user_id = VaultDriver.generate_uid
        uri = URI(@url + "auth/#{application_name}/map/user-id/#{user_id}")
        req = Net::HTTP::Post.new(uri)
        req['X-Vault-Token'] = @token
        application_data = { 'value' => application_id }
        res = Net::HTTP.start(uri.hostname, uri.port) do |http|
            req.body = application_data.to_json
            http.request(req)
        end
        [user_id, res.code.to_i]
    end

    # (4) initialization. create a user under an existing application.
    # * +application_name+ - +string+
    # * +application_id+ - +string+
    # * +user_id+ - +string+
    # returns: user_token - +string+ and code - +integer+ the creation http code
    def create_user_token(user_id, application_id, application_name)
        res = nil
        uri = URI(@url + "auth/#{application_name}/login")
        req = Net::HTTP::Post.new(uri)
        req['X-Vault-Token'] = @token
        application_data = { 'app_id' => application_id, 'user_id' => user_id }
        res = Net::HTTP.start(uri.hostname, uri.port) do |http|
            req.body = application_data.to_json
            http.request(req)
        end
        [JSON.parse(res.body), res.code.to_i]
    end

    # creates a full application set: application path, application id, user id and user token
    # * +application_name+ - +string+ the required name for the application.
    def create_appliction_set(application_name, keys)
        results = {}
        code = unlock_vault(keys)
        return code, nil if code > 399
        code = init_application(application_name)
        return code, nil if code > 399
        results[:app_id], code = create_application_id application_name
        return code, results if code > 399
        results[:user_id], code = create_user(application_name, results[:app_id])
        return code, results if code > 399
        results[:user_data], code = create_user_token(results[:user_id], results[:app_id], application_name)
        return code, results if code > 399
        [200, results]
    end
end
