require_relative "../betterez/SecurityChecker"
require_relative "../betterez/Helpers"
require_relative "mocks/SecurityCheckerMock"
require "test/unit"

class SecurityCheckerTest <Test::Unit::TestCase
  def setup
    @checker=SecurityChecker.new
    @mock_checker=SecurityCheckerMock.new
    @mock_checker.get_all_aws_keys
  end

  def test_mock_data
    data=@mock_checker.load_mock_data
    assert(!data[:users].nil?)
    assert(data[:users]==["consol.user","api.user"],"bad data loaded, #{data[:users]}")
  end

  def test_mock_checker
    assert(@mock_checker.all_users==["consol.user","api.user"],"@mock_checker.all_users=#{@mock_checker.all_users}")
    assert(@mock_checker.all_users!=["console.user","api.user"],"@mock_checker.all_users=#{@mock_checker.all_users}")
    assert(@mock_checker.all_users_keys[:"api.user"].class==Array)
    assert(@mock_checker.all_users_keys[:"api.user"][0][:usage].class==Date,"class usage is #{@mock_checker.all_users_keys[:"api.user"][0][:usage].class}, not Date.")
    assert(@mock_checker.all_users_keys[:"api.user"][0][:usage]>Date.new(2017,8,22))
    assert(@mock_checker.all_users_keys[:"api.user"][0][:usage]<Date.new(2017,8,24))

    assert(@mock_checker.keys_data_index[:AKIA11111111111111111111][:usage].class==NilClass,"class usage is #{@mock_checker.keys_data_index[:AKIA222222222222222222][:usage].class}, not NilClass.")
    assert(@mock_checker.keys_data_index[:AKIA222222222222222222][:usage].class==Date,"class usage is #{@mock_checker.keys_data_index[:AKIA222222222222222222][:usage].class}, not Date.")
    assert(@mock_checker.keys_data_index[:AKIA222222222222222222][:usage]>Date.new(2016,12,12))
    assert(@mock_checker.keys_data_index[:AKIA222222222222222222][:usage]<Date.new(2018,12,12))
  end

  def test_key_validity
    result,err=@mock_checker.check_key_validity({key_name: :aws, key_value: AKIA222222222222222222})
    assert(result=="valid","results should be valid, got #{result}")
  end

  def test_param_extract
    params="data1=123,data2=2"
    value=@checker.get_key_value_for_param("data1",params)
    assert(value!=nil,"value shouldn't be nill")
    assert(value=="123","wanted #{123}, got #{value}")

    value=@checker.get_key_value_for_param("data2",params)
    assert(value!=nil,"value shouldn't be nill")
    assert(value=="2","wanted 2, got #{value}")

    value=@checker.get_key_value_for_param("data3",params)
    assert(value==nil,"value should be nill")

    params="data1=123,data2=hello"
    value=@checker.get_key_value_for_param("data2",params)
    assert(value=="hello","value should be hello, got #{value}")

    params="data1=123,data2=hello,data3=world"
    value=@checker.get_key_value_for_param("data2",params)
    assert(value=="hello","value should be hello, got #{value}")
  end

  def test_service_params
    aws_key="AKIXXXXXXXXXXXXXX"
    mongo_key="q1w2e3r4t5"
    mongo_username="mongo_user"
    service_params="AWS_SERVICE_KEY=#{aws_key},MONGO_DB_PASSWORD=#{mongo_key},MONGO_DB_USERNAME=#{mongo_username}"
    values=@checker.check_service_params(service_params)
    assert(values!=nil)
    assert(values.include?({key_name: :aws, key_value: aws_key}),"failed for #{values}")
    assert(values.include?({key_name: :mongo, key_value: mongo_username}),"failed for #{values}")
    assert(!values.include?({key_name: :mongo, key_value: mongo_username+"12"}),"mongo user should not be found in #{values}")
  end
end
