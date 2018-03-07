require_relative "../betterez/SecurityChecker"
require_relative "../betterez/Helpers"
require_relative "mocks/SecurityCheckerMock"
require "test/unit"

class SecurityCheckerTest <Test::Unit::TestCase
  def setup
    @checker=SecurityChecker.new
    @checker2=SecurityCheckerMock.new
    @checker2.get_all_aws_keys
  end

  def test_mock_data
    data=@checker2.load_mock_data
    assert(!data[:users].nil?)
    assert(data[:users]==["consol.user","api.user"],"bad data loaded, #{data[:users]}")
  end

  def test_checker2
    assert(@checker2.all_users==["consol.user","api.user"],"@checker2.all_users=#{@checker2.all_users}")
    assert(@checker2.all_users!=["console.user","api.user"],"@checker2.all_users=#{@checker2.all_users}")
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
