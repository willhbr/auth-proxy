require "crypto/bcrypt/password"

require "json"

TOKEN_TIMEOUT = 2.days

class UserStore
  JSON.mapping(
    users: Array(User),
  )

  def initialize
    @users = Array(User).new
  end

  class User
    def initialize(@name, @password_hash, @tokens)
    end
    JSON.mapping(
      name: String,
      password_hash: String,
      tokens: Array(Token),
    )
  end

  class Token
    def initialize(@value, @valid_until)
    end
    JSON.mapping(
      valid_until: Time,
      value: String,
    )
  end
end

class Users
  # Username => password
  @registered = Hash(String, String).new
  @user_tokens = Hash(String, Array(String)).new
  @tokens = Hash(String, Time).new

  def initialize(file : String)
    if File.exists? file
      store = UserStore.from_json(File.read(file))
    else
      store = UserStore.new
    end
    store.users.each do |user|
      @registered[user.name] = user.password_hash
      @user_tokens[user.name] = user.tokens.map(&.value)
      user.tokens.each do |token|
        @tokens[token.value] = token.valid_until
      end
    end
    Log.info "Loading logins for #{@registered.size} users, #{@tokens.size} tokens"
  end

  def save(file)
    store = UserStore.new
    p self
    @registered.each do |name, password|
      tokens = (@user_tokens[name]? || [] of String).map do |token|
        UserStore::Token.new(
          valid_until: @tokens[token],
          value: token,
        )
      end
      store.users.push(
        UserStore::User.new(
          name: name,
          password_hash: password,
          tokens: tokens,
        )
      )
    end
    File.write(file, store.to_json)
  end

  def register_user(user, password)
    hashed = Crypto::Bcrypt::Password.create(password, cost: 10)
    @registered[user] = hashed.to_s
  end

  def login_user(user, password)
    expected_password = @registered[user]?
    return false unless expected_password
    Crypto::Bcrypt::Password.new(expected_password) == password
  end

  def valid_token?(token)
    valid_until = @tokens[token]?
    return false unless valid_until
    Time.now < valid_until
  end

  def make_token_for(user, time)
    id = UUID.random.to_s
    @tokens[id] = time
    @user_tokens[user] ||= [] of String
    @user_tokens[user] << id
    id
  end
end
