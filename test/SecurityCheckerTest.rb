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
end
