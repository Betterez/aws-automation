
require 'thread'
class Transaction
  def initialize require_count
    @counter =0
    @require_count=require_count
    @mutex=Mutex.new
  end
  def increase!
    @mutex.synchronize{
      @counter+=1
    }
  end
  def reached_goal?
    left=0
    @mutex.synchronize{
      left=@require_count- @counter
    }
    return (left <= 0)
  end
  attr_reader(:counter)
  attr_reader(:require_count)
end
