require_relative "../betterez/SecurityChecker"
require_relative "../betterez/Helpers"
require_relative "mocks/SecurityCheckerMock"
require "test/unit"

class SecurityCheckerTest <Test::Unit::TestCase
  def setup
    @mock_checker=SecurityCheckerMock.new
    @mock_checker.get_all_aws_keys
  end

  def test_mock_data
    data=@mock_checker.load_mock_data
    assert(!data[:users].nil?)
    assert(data[:users]==["consol.user","api.user","sample1"],"bad data loaded, #{data[:users]}")
  end

  def test_mock_checker
    assert(@mock_checker.all_users==["consol.user","api.user","sample1"],"@mock_checker.all_users=#{@mock_checker.all_users}")
    assert(@mock_checker.all_users!=["console.user","api.user","sample1"],"@mock_checker.all_users=#{@mock_checker.all_users}")
    assert(@mock_checker.all_users_keys[:"api.user"].class==Array)
    assert(@mock_checker.all_users_keys[:"api.user"][0][:usage].class==Time,"class usage is #{@mock_checker.all_users_keys[:"api.user"][0][:usage].class}, not Time.")
    assert(@mock_checker.all_users_keys[:"api.user"][0][:usage]>Time.new(2017,8,22))
    assert(@mock_checker.all_users_keys[:"api.user"][0][:usage]<Time.new(2017,8,24))

    assert(@mock_checker.all_users_keys[:"api.user"][0][:created_date].class==Time,"class created_date is #{@mock_checker.all_users_keys[:"api.user"][0][:created_date].class}, not Time.")
    assert(@mock_checker.all_users_keys[:"api.user"][0][:created_date]>Time.new(2015,3,6))
    assert(@mock_checker.all_users_keys[:"api.user"][0][:created_date]<Time.new(2015,3,8))

    assert(@mock_checker.keys_data_index[:AKIA11111111111111111111][:usage].class==NilClass,"class usage is #{@mock_checker.keys_data_index[:AKIA222222222222222222][:usage].class}, not NilClass.")
    assert(@mock_checker.keys_data_index[:AKIA222222222222222222][:usage].class==Time,"class usage is #{@mock_checker.keys_data_index[:AKIA222222222222222222][:usage].class}, not Time.")
    assert(@mock_checker.keys_data_index[:AKIA222222222222222222][:usage]>Time.new(2016,12,12))
    assert(@mock_checker.keys_data_index[:AKIA222222222222222222][:usage]<Time.new(2018,12,12))
  end

  def test_user_update_key
    result,error=@mock_checker.update_user_iam_keys({"sample1": @mock_checker.all_users_keys[:sample1]})
    assert(!result.nil?)
    assert(result.class==Hash)
    assert(result[:access_key][:access_key_id]=="AKIAIOSFODNN7EXAMPLE","result key should be AKIAIOSFODNN7EXAMPLE, got #{result[:access_key][:access_key_id]}")
    assert(error.nil?,"key should be created if only one exists, but we got #{error}")

  end

  def test_key_validity
    result,err=@mock_checker.check_key_validity({key_name: :aws, key_value: "AKIA222222222222222222"})
    expected="invalid"
    assert(result==expected,"results should be #{expected}, got #{result}")
    @mock_checker.days_to_validate=5000
    result,err=@mock_checker.check_key_validity({key_name: :aws, key_value: "AKIA222222222222222222"})
    expected="valid"
    assert(result==expected,"results should be #{expected}, got #{result}")
  end

  def test_delete_elegibility
    assert(false==@mock_checker.aws_key_can_be_deleted({key_name: :aws, key_value: "AKIA11111111111111111111"}))
  end

  def test_users_data
    assert(@mock_checker.all_users_keys[:"consol.user"].class==Array)
    assert(@mock_checker.all_users_keys[:"consol.user"].length==1)
    # keys are listed in an array
    assert(@mock_checker.all_users_keys[:"consol.user"][0].has_key?(:key_id),"should have a key id as a symbol")
    assert(@mock_checker.all_users_keys[:"consol.user"][0].has_key?(:usage),"should have a usage as a symbol")
    assert(@mock_checker.all_users_keys[:"consol.user"][0].has_key?(:created_date),"should have a created_date as a symbol")
    assert(@mock_checker.all_users_keys[:"consol.user"][0].has_key?(:username),"should have a username as a symbol")
    assert(@mock_checker.all_users_keys.keys[0].class==Symbol,"username should be a symbol")
    assert(@mock_checker.all_users_keys.keys[0].class!=String,"username should not be a string")
    assert(@mock_checker.all_users_keys[@mock_checker.all_users_keys.keys[0]].length==1 ,"should be able to access data through keys array")


    assert(!@mock_checker.all_users_keys[:"consol.user"][0].has_key?("key_id"),"should not have key id as a string")
    assert(@mock_checker.all_users_keys[:"consol.user"][0][:key_id]=="AKIA11111111111111111111")

    assert(@mock_checker.all_users_keys[:"api.user"].class==Array)
    assert(@mock_checker.all_users_keys[:"api.user"].length==2)
  end

  def test_param_extract
    params="data1=123,data2=2"
    value=@mock_checker.get_key_value_for_param("data1",params)
    assert(value!=nil,"value shouldn't be nill")
    assert(value=="123","wanted #{123}, got #{value}")

    value=@mock_checker.get_key_value_for_param("data2",params)
    assert(value!=nil,"value shouldn't be nill")
    assert(value=="2","wanted 2, got #{value}")

    value=@mock_checker.get_key_value_for_param("data3",params)
    assert(value==nil,"value should be nill")

    params="data1=123,data2=hello"
    value=@mock_checker.get_key_value_for_param("data2",params)
    assert(value=="hello","value should be hello, got #{value}")

    params="data1=123,data2=hello,data3=world"
    value=@mock_checker.get_key_value_for_param("data2",params)
    assert(value=="hello","value should be hello, got #{value}")
  end

  def test_service_params
    aws_key="AKIXXXXXXXXXXXXXX"
    mongo_key="q1w2e3r4t5"
    mongo_username="mongo_user"
    service_params="AWS_SERVICE_KEY=#{aws_key},MONGO_DB_PASSWORD=#{mongo_key},MONGO_DB_USERNAME=#{mongo_username}"
    values=@mock_checker.check_service_params(service_params)
    assert(values!=nil)
    assert(values.include?({key_name: :aws, key_value: aws_key}),"failed for #{values}")
    assert(values.include?({key_name: :mongo, key_value: mongo_username}),"failed for #{values}")
    assert(!values.include?({key_name: :mongo, key_value: mongo_username+"12"}),"mongo user should not be found in #{values}")
  end
end
