require_relative "../betterez/SecurityChecker"
require "test/unit"

class SecurityCheckerTest <Test::Unit::TestCase
  def setup
    @checker=SecurityChecker.new
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
    service_params="AWS_SERVICE_KEY=AKIXXXXXXXXXXXXXX,MONGO_DB_PASSWORD=q1w2e3r4t5,MONGO_DB_USERNAME=q1w2e3r4"
    values=@checker.check_service_params(service_params)
    assert (values!=nil)
    values.include?({key_name: "AWS_SERVICE_KEY", key_value: "AKIXXXXXXXXXXXXXX"})
    values.include?({key_name: "MONGO_DB_PASSWORD", key_value: "q1w2e3r4t5"})
    values.include?({key_name: "MONGO_DB_USERNAME", key_value: "q1w2e3r4"})
  end
end
