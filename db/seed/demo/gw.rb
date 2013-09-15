# encoding: utf-8

## ---------------------------------------------------------
## gw/webmail

current_user = Sys::User.find(1)

Sys::User.find(:all, :order => :id).each do |user|
  Gw::WebmailAddress.create(
    :user_id => current_user.id,
    :name    => user.name,
    :email   => user.email
  )
end

Gw::WebmailTemplate.create(
  :user_id      => current_user.id,
  :name         => "テンプレート１",
  :to           => "",
  :body         => "○○市 ○○様\n",
  :default_flag => 1
)

Gw::WebmailSign.create(
  :user_id      => current_user.id,
  :name         => "署名１",
  :body         => ("="*40) + "\nジョールリ市 ○○部○○課\n○○ ○○様\n#{current_user.email}\n" + ("="*40),
  :default_flag => 1
)

Gw::WebmailFilter.create(
  :user_id          => current_user.id,
  :state            => "enabled",
  :name             => "迷惑メール",
  :sort_no          => 1,
  :action           => "delete",
  :mailbox          => "",
  :conditions_chain => "and",
  :in_columns       => {"0" => "subject"},
  :in_inclusions    => {"0" => "<"},
  :in_values        => {"0" => "広告"}
)

