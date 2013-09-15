# encoding: utf-8
module Gw::MailHelper
  
  def recent_maintenance
    item = Sys::Maintenance.new.public
    item.find(:first, :order => 'published_at DESC')  
  end
  
  def mail_form_style
    @mail_form_size = Gw::WebmailSetting.user_config_value(:mail_form_size, 'medium') unless @mail_form_size
    "resizable=yes,scrollbars=yes,width=#{mail_form_size(@mail_form_size)[:window]}"
  end
  
  def open_mail_form(uri)
    uri = escape_javascript(uri)
    "openMailForm('#{uri}', '#{mail_form_style}');return false;"
  end
  
  def mail_form_size(size_name)
    rtn = {
      'small'  => {:window => 800, :container => 770, :textarea => 675 },
      'medium' => {:window => 900, :container => 870, :textarea => 775 },
      'large'  => {:window => 1000, :container => 970, :textarea => 875 }
    }[size_name]
    rtn = {} unless rtn
    rtn
  end
  
  def mail_text_wrap(text, col = 1, options = {})
    
    to_nbsp = lambda do |txt|
      txt.gsub(/(^|\t| ) +/) {|m| m.gsub(' ', '&nbsp;')}
    end
    
    text = "#{text}".force_encoding('utf-8')
    text = text.gsub(/\t/, "  ")
    text = text_wrap(text, col, "\t") unless request.env['HTTP_USER_AGENT'] =~ /MSIE/
    if options[:auto_link]
      http_pattern = 'h\t?t\t?t\t?p\t?s?\t?:\t?\/\t?\/[a-zA-Z0-9_\.\/~%:#\?=&;\-@\+\$,!\*\'\(\)\t]+'
      mail_pattern = '\w\t?[\w\._\-\+\t]*@[\w\._\-\+\t]+'
      target = text
      text = ''.html_safe
      while target && match = target.match(/(#{http_pattern})|(#{mail_pattern})/i)
        if match[1]
          text << to_nbsp.call(h(target[0, match.begin(1)]))
          text << link_to(match[1], match[1].gsub("\t", ''), :target => '_blank')
          target = target[match.end(1), target.size]
        elsif match[2]
          text << to_nbsp.call(h(target[0, match.begin(2)]))
          addr = match[2].gsub("\t", '')
          uri = new_gw_webmail_mail_path(:to => addr)
          text << link_to(match[2], uri, :onclick => open_mail_form(uri))
          target = target[match.end(2), target.size]
        end
      end
      text << to_nbsp.call(h(target)) if target
    else
      text = h(text)
      text = to_nbsp.call(text)
    end
    text = text.gsub(/\t/, '<wbr></wbr>')
    br(text)
  end
  
  def omit_from_address_in_mail_list(from)
    return from unless from
    @from_address_pattern1_in_mail_list ||= /^(.+)<(.+)>\s*(他|$)/
    @from_address_pattern2_in_mail_list ||= /^(.+?)(他|$)/
    addr = from
    match = from.match(@from_address_pattern1_in_mail_list) || from.match(@from_address_pattern2_in_mail_list)
    if match
      from = match[1].strip
      from = "#{from} 他" if match[3] ? !match[3].blank? : !match[2].blank? 
      addr = (match[3] ? match[2] : match[1]).strip 
    end
    [from, addr]
  end
  
  def omit_from_addresses_in_mail_list(froms, options = {})
    froms = froms.map do |from|
      from, addr = omit_from_address_in_mail_list(from)
      if options[:auto_link]
        to = (from == addr ? from : "#{from} <#{addr}>")
        from = link_to(from, new_gw_webmail_mail_path(:to => to))
      end
      from
    end
    froms.join(", ")
  end
  
  def extract_address_from_mail_list(from)
    if from.match(/<(.+)>/)
      from = $1
    end
    from
  end
  
  def extract_addresses_from_mail_list(froms)
    froms ||= ""
    froms.split(/,/).map do |from|
      extract_address_from_mail_list(from)
    end
  end
  
  def candidate_mail_list_limit
      [[20, 20], [30, 30], [40, 40], [50, 50]]
  end
  
  def mailbox_mobile_image_tag(mailbox_type, options = {})
    img = ""
    postfix = "-blue" if options[:blue]
    case mailbox_type
    when 'inbox'
      img = %Q{<img src="/_common/themes/admin/gw/webmail/mobile/images/transmit#{postfix}.jpg" alt="受信トレイ" />}
    when 'drafts'
      img = %Q{<img src="/_common/themes/admin/gw/webmail/mobile/images/draft#{postfix}.jpg" alt="下書き" />}
    when 'sent'
      img = %Q{<img src="/_common/themes/admin/gw/webmail/mobile/images/mailbox#{postfix}.jpg" alt="送信トレイ" />}
    when 'archives'
      img = %Q{<img src="/_common/themes/admin/gw/webmail/mobile/images/archive#{postfix}.jpg" alt="アーカイブ" />}
    when 'trash'
      img = %Q{<img src="/_common/themes/admin/gw/webmail/mobile/images/dustbox#{postfix}.jpg" alt="ごみ箱" />}
    when 'arvhives'
      img = %Q{<img src="/_common/themes/admin/gw/webmail/mobile/images/archive#{postfix}.jpg" alt="アーカイブ" />}
    when 'folder'
      img = %Q{∟}
    else
      img = %Q{<img alt="フォルダ" src="/_common/themes/admin/gw/webmail/mobile/images/folder-white.jpg" alt="フォルダ" />}
    end
    img
  end
  
end