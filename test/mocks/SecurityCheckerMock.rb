require_relative "../../betterez/SecurityChecker"
class SecurityCheckerMock < SecurityChecker

  def get_all_aws_keys
    data=load_mock_data
    throw "can't load data" if data.nil?
    @all_users=data[:users]
    @all_users_keys=data[:keys_by_user]
    @keys_data_index=data[:keys_by_key_value]
    # 
    # @all_users_keys.keys.each do |username|
    #   @all_users_keys[username].each do |user_entry|
    #     if !user_entry[:usage].nil? then
    #       user_entry[:usage]
    #     end
    #   end
    # end
  end

  def load_mock_data
    data=Helpers.load_json_data_to_hash("./test/mock_data/security_info.json")
    data
  end

end
