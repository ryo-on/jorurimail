# encoding: utf-8
module Gw::MailboxHelper
  
  def mailbox_selection(mailboxes)
    selection = []
    mailboxes.each do |box|
      selection << [box.slashed_title, box.id]
    end
    selection
  end
end