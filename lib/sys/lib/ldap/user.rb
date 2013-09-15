# encoding: utf-8
class Sys::Lib::Ldap::User < Sys::Lib::Ldap::Entry
  ## Initializer.
  def initialize(connection, attributes = {})
    super
    @primary = "uid"
    @filter  = "(&(objectClass=top)(objectClass=organizationalPerson))"
  end
  
  ## Attribute: uid
  def uid
    get(:uid)
  end
  
  ## Attribute: name
  def name
    get(:cn)
  end
  
  ## Attribute: name(english)
  def name_en
    "#{get('sn;lang-en')} #{get('givenName;lang-en')}".strip
  end
  
  ## Attribute: email
  def email
    get(:mail)
  end
  
  ## Attribute: kana
  def kana
    get(:cn, 1)
  end
end
