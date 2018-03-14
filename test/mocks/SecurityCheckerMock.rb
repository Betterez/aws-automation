require_relative "../../betterez/SecurityChecker"
class SecurityCheckerMock < SecurityChecker

  def get_all_aws_keys
    data=load_mock_data
    throw "can't load data" if data.nil?
    @all_users=data[:users]
    @all_users_keys=data[:keys_by_user]
    @keys_data_index=data[:keys_by_key_value]

    @all_users_keys.keys.each do |username|
      @all_users_keys[username].each do |user_entry|
        if !user_entry[:usage].nil? then
          user_entry[:usage]=Time.parse(user_entry[:usage])
        end
        if !user_entry[:created_date].nil? then
          user_entry[:created_date]=Time.parse(user_entry[:created_date])
        end
      end
    end

    @keys_data_index.keys.each do |key_name|
      if (!@keys_data_index[key_name][:usage].nil?)
        @keys_data_index[key_name][:usage]=Time.parse(@keys_data_index[key_name][:usage])
      end
      if (!@keys_data_index[key_name][:created_date].nil?)
        @keys_data_index[key_name][:created_date]=Time.parse(@keys_data_index[key_name][:created_date])
      end
    end

  end

  def load_mock_data
    data=Helpers.load_json_data_to_hash("./test/mock_data/security_info.json")
    data
  end

  def create_aws_access_key_for_user(username)
    return {
      access_key: {
      access_key_id: "AKIAIOSFODNN7EXAMPLE",
      create_date: Time.now,
      secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYzEXAMPLEKEY",
      status: "Active",
      user_name: username,
      },}
  end

  def delete_iam_access_key(user_key_info)
    return {}
  end

end
