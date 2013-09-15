# encoding: utf-8
class Gw::Admin::Webmail::ApiController < ApplicationController
  include Sys::Controller::Admin::Auth
  protect_from_forgery :except => [:unseen, :mobile_user]
  
  def unseen
    @account = ""
    @unseen = -1
    @mailboxes = []
    
    if !params[:account].blank? && !params[:password].blank?
      @account = params[:account]
      login_temporarily(params[:account], params[:password]) do
        @unseen = 0
        @mailboxes = Gw::WebmailMailbox.load_mailboxes
        @mailboxes.each do |box|
          @unseen += box.unseen
        end
      end
    end
    
    respond_to do |format|
      format.xml { }
    end
  end
  
protected
  
  def login_temporarily(account, password)
    if new_login(params[:account], params[:password])
      Core.user          = current_user
      Core.user.password = Util::String::Crypt.decrypt(session[PASSWD_KEY])
      Core.user_group    = current_user.groups[0]
      yield
      reset_session
    end
  end
end
