class Sys::Session < ActiveRecord::Base
  set_table_name 'sessions'
  
  def self.delete_past_sessions_at_random(rand_max = 10000)
    return unless rand(rand_max) == 0
    self.delete_expired_sessions
  end
  
  def self.delete_expired_sessions
    expiration = Application.config(:session_expiration, 24*3)
    self.delete_all(["created_at < ?", expiration.hours.ago])
  end
  
end