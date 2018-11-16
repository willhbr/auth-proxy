require "./users"

password_file = ARGV[0]
store = Users.new(password_file)

puts "username: "
username = gets

puts "password: "
password = gets

unless username && password
  puts "Didn't work"
  exit
end

store.register_user(username, password)

store.save("output.txt")
