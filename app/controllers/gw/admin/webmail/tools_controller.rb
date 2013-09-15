# encoding: utf-8
class Gw::Admin::Webmail::ToolsController < Gw::Controller::Admin::Base
  include Sys::Controller::Scaffold::Base
  layout "admin/gw/webmail"
  
  def batch_delete
    @mailboxes = Gw::WebmailMailbox.load_mailboxes
    mailbox_id = params[:mailbox_id]
    start_date = params[:start_date]
    end_date = params[:end_date]
    
    if !mailbox_id || !start_date || !end_date || start_date.empty? || end_date.empty?
      return url_for(:action => :batch_delete)
    end
    
    delete_num = delete_mails_from_to(mailbox_id.to_i, start_date, end_date)
    
    flash[:notice] = "#{delete_num}件のメールを削除しました。"
    redirect_to url_for(:action => :batch_delete)
  end
  
protected

  def delete_mails_from_to(mailbox_id, start_date, end_date)
    num = 0
    
    @mailboxes.each do |box|
      next if mailbox_id != 0 && mailbox_id != box.id 
      
      cond = Condition.new do |c|
        c.and :user_id, Core.user.id
        c.and :mailbox, box.name
        c.and :message_date, '>=', "#{start_date} 00:00:00"
        c.and :message_date, '<=', "#{end_date} 23:59:59"
      end
      
      uids = Gw::WebmailMailNode.find(:all, :conditions => cond.where).map{|item| item.uid}
      Gw::WebmailMailNode.delete_all(cond.where)
      
      Core.imap.select(box.name)
      num += Core.imap.uid_store(uids, "+FLAGS", [:Deleted]).size rescue 0
      Core.imap.expunge
    end
    
    Gw::WebmailMailbox.load_mailboxes(:all)
    Gw::WebmailMailbox.load_quota(:force)
    num
  end
end