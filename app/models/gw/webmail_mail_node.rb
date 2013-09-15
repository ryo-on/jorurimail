# encoding: utf-8
class Gw::WebmailMailNode < ActiveRecord::Base
  include Sys::Model::Base
  include Sys::Model::Auth::Free

  validates_presence_of :user_id, :uid, :mailbox
  
  def self.delete_nodes(boxname, uids = nil)
    dcon = Condition.new do |c|
      c.and :user_id, Core.user.id
      c.and :mailbox, boxname
      if uids.is_a?(Array)
        c.and :uid, 'IN', uids 
      elsif uids
        c.and :uid, uids
      end
    end
    Gw::WebmailMailNode.delete_all(dcon.where)    
  end
  
  def readable
    self.and :user_id, Core.user.id
    self
  end
  
  def editable?
    return true if Core.user.has_auth?(:manager)
    user_id == Core.user.id
  end
  
  def deletable?
    return true if Core.user.has_auth?(:manager)
    user_id == Core.user.id
  end
end
