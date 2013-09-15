# encoding: utf-8
require 'mail'
require 'mail/field'
require 'mail/fields/common/common_address'

#Mail::UnstructuredField.module_eval do
#  def encode_with_fix(value)
#    encode_without_fix(value.encode(charset))
#  end
#  alias_method_chain :encode, :fix
#end
#
#Mail::Message.module_eval do
#  def charset=(value)
#    @defaulted_charset = false
#    @charset = value
#    @header.charset = value
#    @body.charset   = value
#  end
#end
#
#Mail::Body.module_eval do
#  def encoded_with_fix(transfer_encoding = '8bit')
#    dec = Mail::Encodings::get_encoding(encoding)
#    if multipart? ||  transfer_encoding == encoding and dec.nil?
#      encoded_without_fix(transfer_encoding)
#    else
#      enc = Mail::Encodings::get_encoding(get_best_encoding(transfer_encoding))
#      enc.encode(dec.decode(raw_source).encode(charset))
#    end
#  end
#  alias_method_chain :encoded, :fix
#end

class Mail::DispositionNotificationToField < Mail::StructuredField

    include Mail::CommonAddress
    
    FIELD_NAME = 'disposition-notification-to'
    CAPITALIZED_FIELD = 'Disposition-Notification-To'
    
    def initialize(value = nil, charset = 'utf-8')
      self.charset = charset
      super(CAPITALIZED_FIELD, strip_field(FIELD_NAME, value), charset)
      self.parse
      self
    end
    
    def encoded
      do_encode(CAPITALIZED_FIELD)
    end
    
    def decoded
      do_decode
    end
end

Mail::Message.class_eval do
  def find_attachment
    #if content_type && header[:content_disposition]
    #  if header[:content_disposition].value =~ /filename=/
    #    filename = unquote(header[:content_disposition].value.gsub(/.*filename=(.*?)(;.*|$)/, '\\1')).strip
    #    filename = ::NKF::nkf('-wx--cp932', filename)
    #    filename = filename.gsub(/^"(.*)"$/, '\\1')
    #    return filename
    #  end
    #end
    
    if header[:content_type]
      ct_value = header[:content_type].value
      if mt = ct_value.match(/;\s*name=(.*?)(;|$)/im)
        if mt[1].strip[0] != '"'
          header[:content_type].value = ct_value[0, mt.begin(1)] + '"' + mt[1].strip + '"' + ct_value[mt.end(1), ct_value.size]
        end
      end
    end
    if header[:content_disposition]
      accept_encoding = 'iso-2022-jp|shift_jis|euc-jp|utf-8'
      cd_value = header[:content_disposition].value
      if mt = cd_value.match(/;\s*filename\*(?:0\*?)?=(?:#{accept_encoding})'(.*?)'/im)
        if mt[1].blank?
          header[:content_disposition].value = cd_value[0, mt.begin(1)] + 'ja' + cd_value[mt.end(1), cd_value.size]
        end
      end
    end
    
    case
    when content_type && header[:content_type].filename
      filename = header[:content_type].filename
    when content_disposition && header[:content_disposition].filename
      filename = header[:content_disposition].filename
    when content_location && header[:content_location].location
      filename = header[:content_location].location
    else
      filename = nil
    end
    
    if filename
      filename.gsub!(/(=\?)SHIFT-JIS(\?[BQ]\?.+?\?=)/i, '\1' + 'Shift_JIS' +'\2')
      input_charset = nil
      if mt = filename.match(/=\?(.+?)\?[BQ]\?.+?\?=/i)
        input_charset = NKFUtil.input_option(mt[1])
      end
      filename = ::NKF::nkf("-wx --cp932 #{input_charset}", filename)
    end
    filename
  rescue => e
    error_log(e)
    nil
  end
end

Mail::FieldList.class_eval do
  
  alias :_add_new_field_backed_up_by_joruri :<<
  
  def <<(new_field)
    if new_field.field.is_a?(Mail::UnstructuredField) && new_field.errors.size > 0
      case new_field.name.downcase.to_s
      when 'content-disposition'
        new_value = _joruri_adjust_param(new_field.value, "filename")
        new_value = _joruri_adjust_rfc2231_filename(new_value)
        begin
          new_field.field = Mail::ContentDispositionField.new(new_value, new_field.charset)
        rescue Mail::Field::ParseError => e
          error_log(e)
        end
      end
    end
    _add_new_field_backed_up_by_joruri(new_field)
  end

  def _joruri_adjust_param(old_value, param)
    match = old_value.match(/;\s*#{Regexp.escape(param)}="(.*?)"\s*(;|$)/im)
    return old_value unless match
    return old_value if match[1].ascii_only?
    
    enc = NKF.guess(match[1])
    nkf_opt = nil
    nkf_opt = NKFUtil.output_option(enc.name) if enc
    nkf_opt = "-w" unless nkf_opt
    encoded = NKF.nkf("-M #{nkf_opt}", match[1]).gsub("\r\n", "\n").gsub(/\n[ \t]+/, ' ')
    return old_value[0, match.begin(1)] + encoded + old_value[match.end(1), old_value.size]
  end

  def _joruri_adjust_rfc2231_filename(old_value)
    target = old_value
    new_value = ''
    while target && match = target.match(/(filename\*(?:[0-9]+\*?)?=)(.*?)(;|$)/im)
      new_value << target[0, match.begin(0)] << match[1]
      if match[2] =~ /^([^']+'[^']*')?(.+)$/im
        if $1.blank? && $2.strip[0] == '"'
          new_value << $2.strip
        else
          new_value << "#{$1}" << $2.force_encoding('binary').gsub(/[\x00-\x1f\x7f-\xff\s\*'\(\)<>@,;:\\"\/\[\]\?=]/n) {|m|
            sprintf('%%%x', m.ord)
          }              
        end
      end
      new_value << match[3]
      target = target[match.end(0), target.size]
    end
    new_value << target if target
    new_value
  end
end

if Util::Config.load(:core)['mail_domain'] == 'demo.joruri.org'
  
  Mail::Message.class_eval do |cls|
  
    def delivery_handler
      cls = Class.new do
        
        def initialize
          @domain = Core.config['mail_domain']
        end
        
        def filter(f)
          return f.addrs if @domain.blank?
          filtered = []
          f.each do |addr|
            filtered << addr if addr.address =~ /[@\.]#{Regexp.escape(@domain)}$/i
          end
          filtered        
        end
        
        def deliver_mail(m)
                  
          to = m.header[:to]
          cc = m.header[:cc]
          bcc = m.header[:bcc]
          m.to = filter(to).join(',') if to
          m.cc = filter(cc).join(',') if cc
          m.bcc = filter(bcc).join(',') if bcc
          
          yield        
        end
      end
      cls.new
    end
  end
end