# encoding: utf-8
require 'net/ssh'
require "net/imap"
require "rexml/document"

class Gw::WebmailMailbox < ActiveRecord::Base
  include Sys::Model::Base
  include Sys::Model::Auth::Free
  
#  attr_accessor :id, :path, :name, :full_name
  attr_accessor :path, :path_was, :name_was
  
  validates_presence_of :title
  validate :validate_title
  
  def self.imap
    Core.imap
  end
  
  def self.imap_mailboxes
    boxes = {:INBOX => [], :Drafts => [], :Sent => [], :Archives => [], :Trash => [], :Etc => []}
    imap.list('', '*').sort {|a, b| a.name <=> b.name}.each do |box|
      type = :Etc
      [:INBOX, :Drafts, :Sent, :Archives, :Trash].each do |name|
        if box.name =~ /^#{name.to_s}(\.|$)/
          type = name
          break
        end
      end
      boxes[type] <<  box
    end
    boxes[:INBOX] + boxes[:Drafts] + boxes[:Sent] + boxes[:Archives] + boxes[:Etc] + boxes[:Trash]
  end
  
  def self.load_mailbox(mailbox)
    if box = find(:first, :conditions => {:user_id => Core.user.id, :name => mailbox})
      imap.select(mailbox)
      imap.expunge
      unseen = imap.status(mailbox, ['UNSEEN'])['UNSEEN']
      if box.unseen != unseen
        box.unseen = unseen
        box.save(:validate => false)
      end
      return box
    end
    load_mailboxes(:all)
    self.new({
      :user_id  => Core.user.id,
      :name     => mailbox,
      :title    => name_to_title(mailbox).gsub(/.*\./, '')
    })
  end
  
  def self.load_mailboxes(reload = nil)
    if reload.class == String
      if box = find(:first, :conditions => {:user_id => Core.user.id, :name => reload})
        status = imap.status(reload, ['MESSAGES', 'UNSEEN', 'RECENT'])
        box.messages = status['MESSAGES']
        box.unseen   = status['UNSEEN']
        box.recent   = status['RECENT']
        reload = nil if box.save
      else
        reload = :all
      end
    end
    
    boxes = find(:all, :conditions => {:user_id => Core.user.id}, :order => :sort_no)
    return boxes if reload == nil && boxes.size > 0
    
    need = ['Drafts', 'Sent', 'Archives', 'Trash']
    (imap_boxes = imap_mailboxes).each do |box|
      need.delete('Drafts')   if box.name == 'Drafts'
      need.delete('Sent')     if box.name == 'Sent'
      need.delete('Trash')    if box.name == 'Trash'
      need.delete('Archives') if box.name == 'Archives'
    end
    if need.size > 0
      need.each {|name| imap.create(name) }
      imap_boxes = imap_mailboxes
    end
    
    imap_box_names = imap_boxes.collect{|b| b.name}
    boxes.each {|box| box.destroy unless imap_box_names.index(box.name) }
    
    imap_boxes.each_with_index do |box, idx|
      item = nil
      boxes.each do |b|
        if b.name == box.name
          item = b
          break
        end
      end
      status = imap.status(box.name, ['MESSAGES', 'UNSEEN', 'RECENT'])
      item ||= self.new
      item.attributes = {
        :user_id  => Core.user.id,
        :sort_no  => idx + 1,
        :name     => box.name,
        :title    => name_to_title(box.name).gsub(/.*\./, ''),
        :messages => status['MESSAGES'],
        :unseen   => status['UNSEEN'],
        :recent   => status['RECENT']
      }
      item.save(:validate => false) if item.changed?
    end
    return find(:all, :conditions => {:user_id => Core.user.id}, :order => :sort_no)
  end
  
  def self.name_to_title(name)
    name = Net::IMAP.decode_utf7(name)
    name = name.gsub(/^INBOX(\.|$)/, '受信トレイ\1')
    name = name.gsub(/^Drafts(\.|$)/, '下書き\1')
    name = name.gsub(/^Sent(\.|$)/, '送信トレイ\1')
    name = name.gsub(/^Trash(\.|$)/, 'ごみ箱\1')
    name = name.gsub(/^Archives(\.|$)/, 'アーカイブ\1')
    name
  end
  
  def self.load_quota(reload = nil)
    conf = Joruri.config.imap_settings
    return nil if conf[:ssh_address].blank?
    
    quota = {}
    cond  = {:user_id => Core.user.id, :name => 'quota_info'}
    st    = Gw::WebmailSetting.find(:first, :conditions => cond)
    
    if reload != :force
      #試験的に、容量取得の回数を1/3にする。
      reload = nil if reload && rand(3) != 0
    end
    
    if !reload && !st.nil?
      begin
        xml = REXML::Document.new(st.value)
        xml.root.elements.each {|e| quota[e.name.intern] = e.text }
      rescue => e
        return nil
      end
      return quota
    end
    
    begin
      dir = conf[:ssh_maildir].gsub('#{account}', Core.user.account)
      opt = {:password => conf[:ssh_password], :timeout => 1}
      ssh = Net::SSH.start(conf[:ssh_address], conf[:ssh_user_name], opt)
      uu  = ssh.exec!("sudo du -sh #{dir}").to_s.force_encoding('utf-8').gsub(/\n$/, '')
      ub  = ssh.exec!("sudo du -sb #{dir}").to_s.force_encoding('utf-8').gsub(/\n$/, '')
      raise "error: du -sh: #{uu}" if uu !~ /^[0-9]/ || uu.scan("\n").size != 0
      raise "error: du -sb: #{ub}" if ub !~ /^[0-9]/ || ub.scan("\n").size != 0
      
      quota_max_size = Application.config(:mailbox_quota_max_size, 300).to_i
      quota_alert_size = Application.config(:mailbox_quota_alert_size, 250).to_i
      
      quota[:total]       = "#{quota_max_size}M" + "B"
      quota[:total_bytes] = quota_max_size * 1000 * 1000 ## margin
      quota[:used]        = uu.gsub(/(\t| ).*/, '') + "B"
      quota[:used_bytes]  = ub.gsub(/(\t| ).*/m, '')
      quota[:usage_rate]  = sprintf('%.1f', quota[:used_bytes].to_f / quota[:total_bytes].to_f * 100).to_f
      quota[:usage_rate]  = 100 if quota[:usage_rate] > 100
      if (mt = quota[:used].match(/(.+)MB/)) && mt[1].to_i >= quota_alert_size
        usable = quota_max_size - mt[1].to_i
        usable = 0 if usable < 0
        quota[:usable] = "#{usable}MB" 
      end
    rescue => e
      quota = nil
    ensure
      ssh.close if ssh && !ssh.closed?
    end
    
    st ||= Gw::WebmailSetting.new(cond)
    st.value = quota ? quota.to_xml(:dasherize => false,:skip_types => true, :root => 'item') : nil
    st.save(:validate => false)
    return quota
  end
  
  def self.exist?(mailbox)
    find(:first, :conditions => {:user_id => Core.user.id, :name => mailbox.to_s}) ? true : false
  end
  
  def readable
    self.and :user_id, Core.user.id
    self
  end
  
  def creatable?
    return true if Core.user.has_auth?(:manager)
    user_id == Core.user.id
  end
  
  def editable?
    return true if Core.user.has_auth?(:manager)
    user_id == Core.user.id
  end
  
  def deletable?
    return true if Core.user.has_auth?(:manager)
    user_id == Core.user.id
  end
  
  def draft_box?(target = :self)
    case target
    when :all      ; name =~ /^Drafts(\.|$)/
    when :children ; name =~ /^Drafts\./
    else           ; name == "Drafts"
    end
  end
  
  def sent_box?(target = :self)
    case target
    when :all      ; name =~ /^Sent(\.|$)/
    when :children ; name =~ /^Sent\./
    else           ; name == "Sent"
    end
  end
  
  def trash_box?(target = :self)
    case target
    when :all      ; name =~ /^Trash(\.|$)/
    when :children ; name =~ /^Trash\./
    else           ; name == "Trash"
    end
  end
  
  def parents_count
    name.gsub(/[^\.]/, '').length
  end
  
  def children
    cond = Condition.new
    cond.and :user_id, Core.user.id
    cond.and :name, '!=', "#{name}"
    cond.and :name, 'like', "#{name}.%"
    items = find(:all, :conditions => cond.where, :order => :sort_no)
    items.delete_if {|x| x.name =~ /#{name}\.[^\.]+\./}
  end
  
  def path
    return @path if @path
    return "" if name !~ /\./
    name.gsub(/(.*\.).*/, '\\1')
  end
  
  def slashed_title(char = "　 ")
    self.class.name_to_title(name).gsub('.', '/')
  end
  
  def indented_title(char = "　 ")
    "#{char * parents_count}#{title}"
  end
  
  def validate_title
    if title =~ /[\.\/\#\\]/
      errors.add :title, "に半角記号（ . / # \\ ）は使用できません。"
    end
  end
end
