module Joruri
  def self.version
    "1.0.0"
  end
  
  def self.config
    $joruri_config ||= {}
    Joruri::Config
  end
  
  class Joruri::Config
    def self.imap_settings
      $joruri_config[:imap_settings]
    end
    
    def self.imap_settings=(config)
      $joruri_config[:imap_settings] = config
    end
  end
end