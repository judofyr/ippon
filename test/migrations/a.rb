migrate "1-initial-schema" do |db|
  db.create_table(:users) do
    primary_key :id
    Text :name, null: false
  end
end

migrate "2-add-email" do |db|
  db.add_column(:users, :email, :text, unique: true)
end

