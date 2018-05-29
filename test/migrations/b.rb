migrate "3-remove-email" do |db|
  db.drop_column(:users, :email)
end

