# encoding: utf-8
class Gw::Admin::Webmail::MailsController < Gw::Controller::Admin::Base
  include Sys::Controller::Scaffold::Base
  include Gw::Controller::Admin::Mobile::Mail
  helper Gw::MailHelper
  layout :select_layout
  
  def pre_dispatch
    return redirect_to :action => 'index' if params[:reset]
    
    @mailbox   = Gw::WebmailMailbox.load_mailbox(params[:mailbox] || 'INBOX')
    @filter    = ["UNDELETED"]
    @sort      = ["DATE"]
    @limit     = 20
    @new_window = params[:new_window].blank? ? nil : 1
    @mail_form_size = Gw::WebmailSetting.user_config_value(:mail_form_size, 'medium') unless params[:action] == 'index'
  end
  
  def load_mailboxes
    reload = flash[:gw_webmail_load_mailboxes]
    flash.delete(:gw_webmail_load_mailboxes)
    Gw::WebmailMailbox.load_quota(reload)
    Gw::WebmailMailbox.load_mailboxes(reload)
  end
  
  def reset_mailboxes(mailbox = @mailbox.name)
    flash[:gw_webmail_load_mailboxes] = mailbox
  end
  
  def load_quota
    Gw::WebmailMailbox.load_quota
  end
  
  def index
    return empty if params[:do] == 'empty'
    
    confs = Gw::WebmailSetting.user_config_values(
      [:mails_per_page, :mail_form_size, :mail_list_from_address, :mail_list_subject, :mail_open_window])
    @limit = confs[:mails_per_page].blank? ? 20 : confs[:mails_per_page] if !request.mobile?
    @mail_form_size = confs[:mail_form_size].blank? ? 'medium' : confs[:mail_form_size]
    @mail_list_from_address = confs[:mail_list_from_address]
    @mail_list_subject = confs[:mail_list_subject]
    @mail_open_window = confs[:mail_open_window]
    
    ## apply filters
    last_uid, recent, error = Gw::WebmailFilter.apply_recents
    reset_mailboxes(:all) if recent
    if @mailbox.name == "INBOX"
      @filter += ["UID", "1:#{last_uid}"] # slows a little
    end
    if error
      flash.now[:notice] ||= ""
      flash.now[:notice]  += "（フィルタ処理がタイムアウトしました。）"
    end
    
    ## search
    filter = @filter
    if params[:search]
      if !params[:s_status].blank?
        filter += ["UNSEEN"] if params[:s_status] == "unseen"
        filter += ["SEEN"]   if params[:s_status] == "seen"
      end
      if !params[:s_column].blank? && !params[:s_keyword].strip.blank?
        keywords = []
        params[:s_keyword].gsub("　", " ").split(/ +/).each do |w|
          next if w.strip.blank?
          keywords << %Q(#{params[:s_column]} "#{w.gsub('"', '\\"')}")
        end
        filter = filter.join(' ') + " " + keywords.join(' ')
      end
    elsif params[:s_from]
      begin
        from_addr = nil
        from = Gw::WebmailMail.new.parse_address(params[:s_from]).first
        from_addr = from.address if from
      rescue => ex
        from_addr = nil
      end
      if @mailbox.name =~ /^(Sent|Drafts)(\.|$)/
        field = "TO"
      else
        field = "FROM"
      end
      filter += [field, from_addr] if from_addr
    end
    @s_params = params.dup; [:controller, :action, :mailbox].each {|n| @s_params.delete(n) }
    
    @mailboxes = load_mailboxes
    @quota = load_quota
    @items = Gw::WebmailMail.find(:all, :select => @mailbox.name, :conditions => filter,
      :sort => @sort, :page => params[:page], :limit => @limit)
  end
  
  def show
    @item  = Gw::WebmailMail.find_by_uid(params[:id], :select => @mailbox.name, :conditions => @filter)
    return error_auth unless @item
    
    if params[:download] == "eml"
      filename = @item.subject + ".eml"
      filename = filename.gsub(/[\/\<\>\|:"\?\*\\]/, '_') 
      filename = URI::escape(filename) if request.env['HTTP_USER_AGENT'] =~ /MSIE/
      msg = @item.rfc822 || @item.mail.to_s
      return send_data(msg, :filename => filename,
        :type => 'message/rfc822', :disposition => 'attachment')
    elsif params[:download]
      return download_attachment(params[:download])
    elsif params[:source]
      msg = @item.rfc822 || @item.mail.to_s
      return send_data(msg.gsub(/\r\n/m, "\n"),
        :type => 'text/plain; charset=utf-8', :disposition => 'inline')
    elsif params[:show_html_image]
      return http_error(404) unless @item.html_mail?
      return respond_to do |format|
        format.xml { render :action => 'show_html' }
      end
    end
    
    Core.title += " - #{@item.subject} - #{Core.user.email}"
    
    if @item.html_mail?
      @html_mail_view = Gw::WebmailSetting.user_config_value(:html_mail_view, 'html')
    end

    if from = @item.parse_address(@item.friendly_from_addr).first
      @from_addr = CGI.escapeHTML(from.address)
      @from_name = ::NKF::nkf('-wx --cp932', from.name).gsub(/\0/, "") if from.name rescue nil
      @from_name = CGI.escapeHTML(@from_name || @from_addr)
    end rescue nil
    
    
    if @item.draft? && @item.mail.header[:bcc].blank? && node = @item.find_node
      @item.mail.header[:bcc] = node.bcc
    end
    
    @item.request_mdn = 1 if @item.has_disposition_notification_to?
    
    if @item.unseen?
      Core.imap.uid_store(@item.uid, "+FLAGS", [:Seen])
      reset_mailboxes
      
      if @item.has_disposition_notification_to?
        @mdnRequest = mdn_request_mode
        if @mdnRequest && @mdnRequest == :auto
          begin
            send_mdn_message(@mdnRequest)
          rescue => e
            flash.now[:notice] = "開封確認メールの自動送信に失敗しました。"
          end
        end
      end
    end
    
    @mailboxes  = load_mailboxes
    
    cond        = { :select => @mailbox.name, :conditions => @filter, :sort => @sort }
    @pagination = @item.single_pagination(params[:id], cond)
    
    _show @item
  end
  
  def download_attachment(no)
    return http_error(404) unless no =~ /^[0-9]+$/
    return http_error(404) unless @file = @item.attachments[no.to_i]
    #return http_error(404) unless @file.name == params[:filename]
    
    filedata    = @file.body
    disposition = @file.image? ? 'inline' : 'attachment'
    if !params[:thumbnail].blank? && data = @file.thumbnail(:width => 480, :height => 360)
      filedata = data
    end
    
    filename = @file.name#@item.mail.unquote(@file.name)
    filename = filename.gsub(/[\/\<\>\|:"\?\*\\]/, '_') 
    filename = URI::escape(filename) if request.env['HTTP_USER_AGENT'] =~ /MSIE/
    
    send_data(filedata, :type => @file.content_type, :filename => filename, :disposition => disposition)
  end
  
  def new
    return false if no_email?
    @form_action = "create"
    
    @item = Gw::WebmailMail.new
    @item.tmp_id  = Sys::File.new_tmp_id
    if default_template
      @item.in_to      = default_template.to
      @item.in_cc      = default_template.cc
      @item.in_bcc     = default_template.bcc
      @item.in_subject = default_template.subject
      @item.in_body    = default_template.body
    end
    if default_sign_body
      @item.in_body  ||= ""
      @item.in_body   += "\n\n#{default_sign_body}"
    end
    
    load_address_from_flash
    
    @item.in_to     = params[:to] if params[:to]
    @item.in_format = Gw::WebmailMail::FORMAT_TEXT 
    
    #@mailboxes  = load_mailboxes
  end
  
  def edit
    return false if no_email?
    @form_action = "update"
    @form_method = "put"
    
    @ref = Gw::WebmailMail.find_by_uid(params[:id], :select => @mailbox.name, :conditions => @filter)
    return http_error(404) unless @ref
    ref_node = @ref.find_node
    
    @item = Gw::WebmailMail.new(params[:item])
    @item.tmp_id     = Sys::File.new_tmp_id
    @item.in_to      = @ref.friendly_to_addrs.join(',')
    @item.in_cc      = @ref.friendly_cc_addrs.join(',')
    @item.in_bcc     = @ref.friendly_bcc_addrs.join(',')
    @item.in_bcc     = ref_node.bcc if @item.in_bcc.blank? && ref_node 
    @item.in_subject = @ref.subject
    if @ref.html_mail?
      @item.in_html_body = @ref.html_body_for_edit
      @item.in_format    = Gw::WebmailMail::FORMAT_HTML         
    else
      @item.in_body      = @ref.text_body
      @item.in_format    = Gw::WebmailMail::FORMAT_TEXT     
    end
    @item.request_mdn = 1 if @ref.has_disposition_notification_to?
    
    load_address_from_flash
    
    load_attachments(@ref, @item)
    
    #@mailboxes  = load_mailboxes
    render(:action => :new)
  end
  
  def answer
    return false if no_email?
    
    sign_position = Gw::WebmailSetting.user_config_value(:sign_position)
    @form_action = "answer"
    
    @ref = Gw::WebmailMail.find_by_uid(params[:id], :select => @mailbox.name, :conditions => @filter)
    return http_error(404) unless @ref
    
    @item = Gw::WebmailMail.new(params[:item])
    @item.reference = @ref
    
    if request.post?
      return send_message(@item) { Core.imap.uid_store(@ref.uid, "+FLAGS", [:Answered]) }
    end
    
    @item.tmp_id     = Sys::File.new_tmp_id
    @item.in_to      = @ref.friendly_reply_to_addrs(!params[:all].blank?).join(', ')
    @item.in_subject = "Re: " + @ref.subject
    if params[:mail_view] == Gw::WebmailMail::FORMAT_HTML && @ref.html_mail?
      @item.in_html_body = "<div>&nbsp;</div>#{@ref.referenced_html_body}"
      @item.in_html_body += Util::String.text_to_html("\n" + default_sign_body) if default_sign_body  
      @item.in_format = Gw::WebmailMail::FORMAT_HTML
    else
      sign_body = ''
      sign_body = "\n\n#{default_sign_body}" if default_sign_body
      @item.in_body = ''
      @item.in_body += "\n\n#{@ref.referenced_body}" if params[:qt]
      if sign_position.blank?
        @item.in_body = sign_body + @item.in_body 
      else
        @item.in_body += sign_body
      end
      @item.in_format = Gw::WebmailMail::FORMAT_TEXT
    end
    
    if params[:all]
      @item.in_cc = @ref.friendly_cc_addrs.join(', ')
    end
    
    load_address_from_flash
    
    #@mailboxes  = load_mailboxes
    render(:action => :new)
  end
  
  def forward
    return false if no_email?
    
    sign_position = Gw::WebmailSetting.user_config_value(:sign_position)
    @form_action = "forward"
    
    @ref = Gw::WebmailMail.find_by_uid(params[:id], :select => @mailbox.name, :conditions => @filter)
    return http_error(404) unless @ref
    
    @item = Gw::WebmailMail.new(params[:item])
    
    if request.post?
      return send_message(@item) { Core.imap.uid_store(@ref.uid, "+FLAGS", "$Forwarded") }
    end
    
    @item.tmp_id      = Sys::File.new_tmp_id
    @item.in_subject  = "Fw: " + @ref.subject
    
    if params[:mail_view] == Gw::WebmailMail::FORMAT_HTML && @ref.html_mail?
      @item.in_html_body = "<div>&nbsp;</div>#{@ref.referenced_html_body(:forward)}"
      @item.in_html_body += Util::String.text_to_html("\n" + default_sign_body) if default_sign_body  
      @item.in_format = Gw::WebmailMail::FORMAT_HTML    
    else
      sign_body = ''
      sign_body = "\n\n#{default_sign_body}" if default_sign_body
      @item.in_body = "\n\n#{@ref.referenced_body(:forward)}"
      if sign_position.blank?
        @item.in_body = sign_body + @item.in_body 
      else
        @item.in_body += sign_body
      end
      @item.in_format = Gw::WebmailMail::FORMAT_TEXT      
    end
    
    load_address_from_flash
    
    load_attachments(@ref, @item)
    
    #@mailboxes  = load_mailboxes
    render(:action => :new)
  end

  def resend
    return false if no_email?
    
    @form_action = "create"
    
    @ref = Gw::WebmailMail.find_by_uid(params[:id], :select => @mailbox.name, :conditions => @filter)
    return http_error(404) unless @ref
    
    @item = Gw::WebmailMail.new
    @item.tmp_id     = Sys::File.new_tmp_id
    @item.in_to      = @ref.friendly_to_addrs.join(', ')
    @item.in_cc      = @ref.friendly_cc_addrs.join(', ')
    @item.in_bcc     = @ref.friendly_bcc_addrs.join(', ')
    @item.in_subject = @ref.subject
    if params[:mail_view] == Gw::WebmailMail::FORMAT_HTML && @ref.html_mail?
      @item.in_html_body = @ref.html_body
      @item.in_format = Gw::WebmailMail::FORMAT_HTML
    else
      @item.in_body = @ref.text_body
      @item.in_format = Gw::WebmailMail::FORMAT_TEXT
    end
    @item.request_mdn = 1 if @ref.has_disposition_notification_to?
    
    load_address_from_flash
    
    load_attachments(@ref, @item)
    
    render(:action => :new)
  end

  def create
    return false if no_email?
    @form_action = "create"
    
    @item = Gw::WebmailMail.new(params[:item])
    send_message(@item)
  end
  
  def update
    return false if no_email?
    @form_action = "update"
    @form_method = "put"
    
    @ref = Gw::WebmailMail.find_by_uid(params[:id], :select => @mailbox.name, :conditions => @filter)
    return http_error(404) unless @ref
    
    @item = Gw::WebmailMail.new(params[:item])
    send_message(@item) do
      Gw::WebmailMailNode.delete_nodes(@mailbox.name, @ref.uid)
      @ref.destroy(true)
    end
  end
  
  def send_message(item, &block)
    config = Gw::WebmailSetting.user_config_value(:mail_from)
    ma = Mail::Address.new
    ma.address      = Core.user.email
    ma.display_name = Core.user.name if config != "only_address"
    item.in_from = ma.to_s
    
    ## submit/destroy
    if !params[:commit_destroy].blank?
      item.delete_tmp_attachments
      return redirect_to(:action => :close)
    end
    
    
    ## submit/draft
    if !params[:commit_draft].blank?
      unless item.valid?(:draft)
        #@mailboxes  = load_mailboxes
        return render(:action => :new)
      end
      return save_as_draft(item, &block)
    end
    
    ## submit/send
    unless item.valid?(:send)
      #@mailboxes  = load_mailboxes
      return render(:action => :new)
    end
    
    begin
      mail = item.prepare_mail(request)
      mail.delivery_method(:smtp, ActionMailer::Base.smtp_settings)
      sent = mail.deliver
      item.delete_tmp_attachments
      #flash[:notice] = 'メールを送信しました。'.html_safe
    rescue => e
      #@mailboxes  = load_mailboxes
      flash.now[:notice] = "メールの送信に失敗しました。（#{e}）"
      respond_to do |format|
        format.html { render :action => :new }
        format.xml  { render :xml => item.errors, :status => :unprocessable_entity }
      end
      return
    end
    
    yield if block_given?
    
    ## save to 'Sent'
    begin
      imap = Core.imap
      #imap.create("Sent") unless imap.list("", "Sent")
      imap.create("Sent") unless Gw::WebmailMailbox.exist?("Sent") rescue nil
      item.mail = sent
      imap.append("Sent", item.for_save.to_s, [:Seen], Time.now)
    rescue => e
      #flash[:notice] += "<br />送信トレイへの保存に失敗しました。（#{e}）".html_safe
      flash[:notice] = "送信トレイへの保存に失敗しました。（#{e}）"
    end
    
    status         = params[:_created_status] || :created
    location       = url_for(:action => :close)
    respond_to do |format|
      format.html { redirect_to(location) }
      format.xml  { render :xml => item.to_xml(:dasherize => false), :status => status, :location => location }
    end
  end
  
  def save_as_draft(item, &block)
    begin
      mail = item.prepare_mail(request)
      imap = Core.imap
      #imap.create("Drafts") unless imap.list("", "Drafts")
      imap.create("Drafts") unless Gw::WebmailMailbox.exist?("Drafts") rescue nil
      next_uid = imap.status("Drafts", ["UIDNEXT"])["UIDNEXT"]
      item.mail = mail
      imap.append("Drafts", item.for_save.to_s, [:Seen, :Draft], Time.now)
      item.delete_tmp_attachments
      
      ## save bcc
      #if mail = Gw::WebmailMail.find(:all, :select => "Drafts", :conditions => ["UID", next_uid]).first
      #  if mail.node.subject == item.in_subject && !item.in_bcc.blank?
      #    mail.node.bcc = item.in_bcc
      #    mail.node.save
      #  end
      #end
      
      yield if block_given?
    rescue => error
      #@mailboxes  = load_mailboxes
      item.errors.add_to_base "下書き保存に失敗しました。（#{error}）"
      flash.now[:notice] = "下書き保存に失敗しました。（#{error}）"
      respond_to do |format|
        format.html { render :action => :new }
        format.xml  { render :xml => item.errors, :status => :unprocessable_entity }
      end
      return
    end
    
    #flash[:notice] = '下書きに保存しました。'
    status         = params[:_created_status] || :created
    location       = url_for(:action => :close)
    respond_to do |format|
      format.html { redirect_to(location) }
      format.xml  { render :xml => item.to_xml(:dasherize => false), :status => status, :location => location }
    end
  end
  
  def destroy
    @item  = Gw::WebmailMail.find_by_uid(params[:id], :select => @mailbox.name, :conditions => @filter)
    return error_auth unless @item
    
    Gw::WebmailMailNode.delete_nodes(@mailbox.name, @item.uid)
    if @item.destroy
      reset_mailboxes(:all)
      flash[:notice] = 'メールを削除しました。' unless @new_window
      respond_to do |format|
        format.html do
          action = @new_window ? :close : :index
          redirect_to url_for(:action => action)
        end
        format.xml  { head :ok }
      end
    else
      flash.now[:notice] = 'メールの削除に失敗しました。'
      respond_to do |format|
        format.html { render :action => :show }
        format.xml  { render :xml => @item.errors, :status => :unprocessable_entity }
      end
    end
  end
  
  ## move_all or move_one
  def move
    if !params[:item] || !params[:item][:ids]
      return redirect_to(url_for(:action => :index, :page => params[:page]))
    end
    
    uids = params[:item][:ids].collect{|k, v| k.to_s =~ /^[0-9]+$/ ? k.to_i : nil }
    cond = ["UID", uids] + @filter
    
    if !params[:item][:mailbox]
      @items = Gw::WebmailMail.find(:all, :select => @mailbox.name, :conditions => cond)
      @mailboxes = load_mailboxes
      return render :template => 'gw/admin/webmail/mails/move'
    end
    
    dcon = Condition.new do |c|
      c.and :user_id, Core.user.id
      c.and :mailbox, @mailbox.name
      c.and :uid, 'IN', uids
    end
    Gw::WebmailMailNode.delete_all(dcon.where) if params[:copy].blank?
    
    Core.imap.select(@mailbox.name)
    response = Core.imap.uid_copy(uids, params[:item][:mailbox])
    num = 0
    if response.name == "OK"
      if params[:copy].blank?
        num = Core.imap.uid_store(uids, "+FLAGS", [:Deleted]).size rescue 0
        Core.imap.expunge
      else
        num = uids.size
      end
    end
    
#    num = 0
#    Gw::WebmailMail.find(:all, :select => @mailbox.name, :conditions => cond).each do |item|
#      num += 1 if item.move(params[:item][:mailbox])
#    end
    
    reset_mailboxes(:all) if num > 0
    label = params[:copy].blank? ? '移動' : 'コピー'
    flash[:notice] = "#{num}件のメールを#{label}しました。".force_encoding('utf-8') unless @new_window
    action = @new_window ? :close : :index
    redirect_to url_for(:action => action, :page => params[:page])
  end
  
  ## destroy_all
  def delete
    if !params[:item] || !params[:item][:ids]
      return redirect_to url_for(:action => :index, :page => params[:page])
    end
    
    uids = params[:item][:ids].collect{|k, v| k.to_s =~ /^[0-9]+$/ ? k.to_i : nil }
    cond = ["UID", uids] + @filter
    
    dcon = Condition.new do |c|
      c.and :user_id, Core.user.id
      c.and :mailbox, @mailbox.name
      c.and :uid, 'IN', uids
    end
    Gw::WebmailMailNode.delete_all(dcon.where)
    
    Core.imap.select(@mailbox.name)
    if !@mailbox.trash_box?(:all)
      Core.imap.uid_copy(uids, 'Trash') rescue nil
    end
    num = Core.imap.uid_store(uids, "+FLAGS", [:Deleted]).size rescue 0
    Core.imap.expunge

#    Gw::WebmailMail.find(:all, :select => @mailbox.name, :conditions => cond).each do |item|
#      num += 1 if item.destroy
#    end
    
    reset_mailboxes(:all) if num > 0
    flash[:notice] = "#{num}件のメールを削除しました。".force_encoding('utf-8')
    redirect_to url_for(:action => :index, :page => 1) #params[:page]
  end
  
  def seen
    if !params[:item] || !params[:item][:ids]
      return redirect_to url_for(:action => :index, :page => params[:page])
    end
    
    uids = params[:item][:ids].collect{|k, v| k.to_s =~ /^[0-9]+$/ ? k.to_i : nil }
    cond = ["UID", uids] + @filter
    
    num = 0
    Core.imap.select(@mailbox.name)
    uids.each do |uid|
      begin
        Core.imap.uid_store(uid, "+FLAGS", [:Seen])
        num += 1
      rescue => e
        #e
      end
    end
    
    reset_mailboxes if num > 0
    flash[:notice] = "#{num}件のメールを既読にしました。".force_encoding('utf-8')
    redirect_to url_for(:action => :index, :page => params[:page])
  end
  
  def unseen
    if !params[:item] || !params[:item][:ids]
      return redirect_to url_for(:action => :index, :page => params[:page])
    end
    
    uids = params[:item][:ids].collect{|k, v| k.to_s =~ /^[0-9]+$/ ? k.to_i : nil }
    cond = ["UID", uids] + @filter
    
    num = 0
    Core.imap.select(@mailbox.name)
    uids.each do |uid|
      begin
        Core.imap.uid_store(uid, "-FLAGS", [:Seen])
        num += 1
      rescue => e
        #e
      end
    end
    
    reset_mailboxes if num > 0
    flash[:notice] = "#{num}件のメールを未読にしました。".force_encoding('utf-8')
    redirect_to url_for(:action => :index, :page => params[:page])
  end
  
  def empty
    reset_mailboxes(:all)
    load_mailboxes.reverse.each do |box|
      if box.trash_box?(:children)
        begin
          Gw::WebmailMailNode.delete_nodes(box.name)
          Core.imap.delete(box.name)
        rescue => e
        end
      end
    end
    
    Gw::WebmailMailNode.delete_nodes(@mailbox.name)
    Core.imap.select(@mailbox.name)
    Core.imap.uid_search(@filter, "utf-8").each do |uid|
      begin
        Core.imap.uid_store(uid, "+FLAGS", [:Deleted])
      rescue => e
      end
    end
    Core.imap.expunge
    
    reset_mailboxes(:all)
    flash[:notice] = "ごみ箱を空にしました。"
    respond_to do |format|
      format.html { redirect_to url_for(:action => :index) }
      format.xml  { head :ok }
    end
  end
  
  def send_mdn
    @item = Gw::WebmailMail.find_by_uid(params[:id], :select => @mailbox.name, :conditions => @filter)
    return error_auth unless @item && @item.has_disposition_notification_to?

    send_mdn_message(params[:send_mode])
  end
  
protected

  def select_layout
    layout = "admin/gw/webmail"
    case params[:action].to_sym
    when :new, :edit, :answer, :forward, :close, :create, :update, :resend
      layout = "admin/gw/mail_form"
    when :show, :move
      unless params[:new_window].blank?
        layout = "admin/gw/mail_form"
      end
    end
    layout
  end
  
  def no_email?
    if Core.user.email.blank?
      error = "メールアドレスが登録されていません。"
      render(:text => error, :layout => true)
      return true
    end
    return nil
  end
  
  def default_sign_body
    return @default_sign.body if @default_sign
    if request.mobile?
      @default_sign = Gw::WebmailSign.new
    else
      @default_sign = (Gw::WebmailSign.default_sign || Gw::WebmailSign.new)
    end
    @default_sign.body
  end
  
  def default_template
    return @default_template if @default_template
    if request.mobile?
      @default_template = Gw::WebmailTemplate.new
    else
      @default_template = (Gw::WebmailTemplate.default_template || Gw::WebmailTemplate.new)
    end
    @default_template
  end
  
  def load_attachments(ref, item)
    if ref.has_attachments?
      ref.attachments.each do |f|
        file = Gw::WebmailMailAttachment.new({
          :tmp_id => item.tmp_id,
        })
        at_file = Sys::Lib::File::NoUploadedFile.new({
          :data     => f.body,
          :filename => f.name
        })
        file.save_file(at_file) # pass the errors
      end
    end
  end
  
  def mdn_request_mode
    mdnRequest = :manual
    domain = Core.config['mail_domain']
    addrs = @item.disposition_notification_to_addrs
    begin
      if !domain.blank? && addrs && addrs.size > 0 &&
        addrs[0].address =~ /[@\.]#{Regexp.escape(domain)}$/i
        mdnRequest = :auto  
      end          
    rescue => e
      #Disposition-Notification-Toのパースエラー対策
      error_log(e)
      mdnRequest = nil
    end
    mdnRequest
  end
  
  def send_mdn_message(mdn_mode)
    mdn = Gw::WebmailMail.new
    mdn.in_from ||= %Q(#{Core.user.name} <#{Core.user.email}>)
    mail = mdn.prepare_mdn(@item, mdn_mode.to_s, request)
    mail.delivery_method(:smtp, ActionMailer::Base.smtp_settings)
    mail.deliver
  end
  
  def load_address_from_flash
    @item.in_to  = flash[:mail_to] if flash[:mail_to]
    @item.in_cc  = flash[:mail_cc] if flash[:mail_cc]
    @item.in_bcc = flash[:mail_bcc] if flash[:mail_bcc]
  end
  
end
