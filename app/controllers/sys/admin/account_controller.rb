# encoding: utf-8
class Sys::Admin::AccountController < Sys::Controller::Admin::Base
  protect_from_forgery :except => [:login]
  
  def login
    skip_layout
    #admin_uri = '/_admin'
    admin_uri = '/_admin/gw/webmail/INBOX/mails'
    
    #return redirect_to(admin_uri) if logged_in?
    
    @uri = params[:uri] || cookies[:sys_login_referrer] || admin_uri
    @uri = @uri.gsub(/^http:\/\/[^\/]+/, '')
    return unless request.post?
    
    if params[:password].to_s == 'p' + params[:account].to_s
      cond = {:account => params[:account]}
      if Sys::User.find(:first, :conditions => cond)
        flash.now[:notice] = "初期パスワードではログインできません。<br />パスワードを変更してください。".html_safe
        respond_to do |format|
          format.html { render }
          format.xml  { render(:xml => '<errors />') }
        end
        return true
      end
    end
    
    if request.mobile?
      login_ok = new_login_mobile(params[:account], params[:password], params[:mobile_password])
    else
      login_ok = new_login(params[:account], params[:password])
    end
    
    unless login_ok
      flash.now[:notice] = "ユーザＩＤ・パスワードを正しく入力してください"
      respond_to do |format|
        format.html { render }
        format.xml  { render(:xml => '<errors />') }
      end
      return true
    end
    
    if params[:remember_me] == "1"
      self.current_user.remember_me
      cookies[:auth_token] = {
        :value   => self.current_user.remember_token,
        :expires => self.current_user.remember_token_expires_at
      }
    end
    
    cookies.delete :sys_login_referrer
    Sys::Session.delete_past_sessions_at_random
      
    respond_to do |format|
      format.html { redirect_to @uri }
      format.xml  { render(:xml => current_user.to_xml) }
    end
  end

  def logout
    self.current_user.forget_me if logged_in?
    cookies.delete :auth_token
    reset_session
    redirect_to('action' => 'login')
  end
  
  def info
    skip_layout
    
    respond_to do |format|
      format.html { render }
      format.xml  { render :xml => Core.user.to_xml(:root => 'item', :include => :groups) }
    end
  end
end
