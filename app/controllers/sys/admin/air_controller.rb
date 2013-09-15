# encoding: utf-8
class Sys::Admin::AirController < ApplicationController
  include Sys::Controller::Admin::Auth
  
  protect_from_forgery :except => [:old_login, :login]
  
  def old_login
    render(:text => "NG")
  end
  
  def login
    @admin_uri = '/_admin/gw/webmail/INBOX/mails'
    
    if params[:account] && params[:password]
      return air_token(params[:account], params[:password])
    elsif params[:account] && params[:token]
      return air_login(params[:account], params[:token])
    end
    render(:text => "NG")
  end
  
  def air_token(account, password)
    user = Sys::User.authenticate(account, password)
    return render(:text => 'NG') unless user
    
    now   = Time.now
    token = Digest::MD5.hexdigest(now.to_f.to_s)
    
    user.air_login_id = "#{token}:#{now.to_i}"
    user.save(:validate => false)
    
    render :text => "OK #{token}"
  end
  
  def air_login(account, token)
    cond = Condition.new do |c|
      c.and :account, account
      c.and :air_login_id, 'IS NOT', nil
      c.and :air_login_id, 'LIKE', "#{token}%"
    end
    user = Sys::User.find(:first, :conditions => cond.where)
    return render(:text => "ログインに失敗しました。") unless user
    
    user.air_login_id = nil
    user.save(:validate => false)
    
    set_current_user(user)
    Sys::Session.delete_past_sessions_at_random
      
    redirect_to @admin_uri
  end
end
