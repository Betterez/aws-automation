class Notifire
  attr_accessor :use_time_stamp
  def initialize
    @use_time_stamp=true
    @show_thread=true
  end
  def notify (code,message)
    return if message==nil
    notification=""
    notification+= "#{Thread.current.object_id}:" if @show_thread
    notification+="#{Time.new()}-#" if @use_time_stamp
    notification+=message
    puts notification
  end
end
