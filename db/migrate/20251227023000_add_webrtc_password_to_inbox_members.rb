class AddWebrtcPasswordToInboxMembers < ActiveRecord::Migration[7.1]
  def change
    add_column :inbox_members, :webrtc_password, :text
  end
end
