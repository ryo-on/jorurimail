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
    delete_num = 0
    
    sent_since = Time.parse(start_date).strftime("%d-%b-%Y")
    sent_before = (Time.parse(end_date) + 1.days).strftime("%d-%b-%Y")
    
    changed_mailboxes = []
    
    @mailboxes.each do |box|
      next if box.name =~ /^(Star)$/
      next if mailbox_id != 0 && mailbox_id != box.id 
      
      condition = ['SENTSINCE', sent_since, 'SENTBEFORE', sent_before]
      condition << 'UNFLAGGED' unless params[:include_starred]
      
      Core.imap.select(box.name)
      uids = Core.imap.uid_search(condition)
      num = Core.imap.uid_store(uids, "+FLAGS", [:Deleted]).size rescue 0
      Core.imap.expunge
      
      if num > 0
        Gw::WebmailMailNode.delete_nodes(box.name, uids)
        changed_mailboxes << box.name
      end
      
      delete_num += num
      
      starred_uids = Gw::WebmailMailNode.find_ref_nodes(box.name, uids).map{|x| x.uid}
      Core.imap.select('Star')
      num = Core.imap.uid_store(starred_uids, "+FLAGS", [:Deleted]).size rescue 0
      Core.imap.expunge
      if num > 0
        Gw::WebmailMailNode.delete_ref_nodes(box.name, uids)
      end
    end
    
    if delete_num > 0
      Gw::WebmailMailbox.load_mailboxes(:all)
      Gw::WebmailMailbox.load_quota(:force)
    end
    
    delete_num
  end
end