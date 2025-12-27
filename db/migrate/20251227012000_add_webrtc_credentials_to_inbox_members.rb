class AddWebrtcCredentialsToInboxMembers < ActiveRecord::Migration[7.1]
  def change
    add_column :inbox_members, :webrtc_username, :string
    add_column :inbox_members, :webrtc_jwt, :text
  end
end
