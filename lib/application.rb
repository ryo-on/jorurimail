# encoding: utf-8
class Application
  
  @@filename = nil
  @@config = {}
  
  @default_menu = {
    :mail_menu          => "メール",
    :mailbox_menu       => "フォルダ",
    :sys_address_menu   => "組織アドレス帳",
    :address_group_menu => "個人アドレス帳",
    :filter_menu        => "フィルタ",
    :template_menu      => "テンプレート",
    :sign_menu          => "署名",
    :memo_menu          => "メモ",
    :tool_menu          => "ツール",
    :setting_menu       => "設定"
  }
  
  def self.initialize
    @@filename = "#{Rails.root}/config/application.yml"
    if File.exists?(@@filename)
      if yaml = YAML.load_file(@@filename)
        @@config = yaml.values[0] || {}
      end
    end
  end
  
  def self.config(name, default = nil)
    initialize unless @@filename
    value = @@config[name.to_s]
    value ? value : default
  end
  
  def self.menu(name)
    self.config(name, @default_menu[name].to_s)
  end
end