require "http/server"
require "http/client"
require "uuid"

require "./config"
require "./logger"
require "./users"

COOKIE_NAME = "cr-proxy-token"

class Proxy
  @config : Config

  def initialize(@config : Config)
    @users = Users.new(@config.password_file)
  end

  def check_authentication(headers) : Symbol
    cookies = headers["Cookie"]?
    return :no_cookie unless cookies
    value = cookies.split("; ").map do |c|
      n, _, v = c.partition '='
      {n, v}
    end.find { |(n, v)| n == COOKIE_NAME }
    return :no_cookie unless value
    token = value[1]
    is_valid = @users.valid_token?(token)
    Log.info "Login using #{token}, token valid? #{is_valid}"
    return :invalid unless is_valid
    :ok
  end

  def respond_authentication(context, status)
    Log.info "Rendering login page"
    context.response.status_code = 401
    context.response.print {{ `cat templates/login.html`.stringify }}
  end

  def login_and_respond(context)
    Log.info "Logging in user"
    io = context.request.body
    return :error unless io
    content = io.gets_to_end
    Log.info("Login info: #{content}")
    params = HTTP::Params.parse(content)
    username = params["username"]
    password = params["password"]
    return :error unless username && password
    unless @users.login_user(username, password)
      return :invalid
    end
    id = @users.make_token_for(username, Time.now)
    context.response.status_code = 200
    context.response.headers.add(
      "Set-Cookie", "#{COOKIE_NAME}=#{id};"
    )
    context.response.print "Logged in as #{username}!"
    return :ok
  end

  def path_to_service_and_proxy(path)
    end_idx = path.byte_index('/'.ord, 1)
    if end_idx
      service = path[1...end_idx]
      proxy_path = path[end_idx...-1]
    else
      service = path[1..-1]
      proxy_path = "/"
    end
    return service, proxy_path
  end

  def proxy
    server = HTTP::Server.new do |context|
      service, proxy_path = path_to_service_and_proxy(context.request.path)
      if service == "login"
        login_and_respond(context)
        next
      end
      found = @config.get_host_and_port(service)
      Log.info "#{service}: #{context.request.method}: #{proxy_path}"
      auth_status = check_authentication(context.request.headers)
      if auth_status != :ok
        Log.info "Authentication failed: #{auth_status}"
        respond_authentication(context, auth_status)
        next
      end
      unless found
        Log.info "No host found for #{service}"
        next
      end
      host, port = found
      client = HTTP::Client.new host, port: port
      request = context.request
      request.path = proxy_path
      response = client.exec request
      context.response.status_code = response.status_code
      context.response.headers.merge! response.headers
      context.response.print response.body
      client.close
    end

    server.bind_tcp @config.host, @config.port
    Log.info "Proxying on http://#{@config.host}:#{@config.port}"
    server.listen
  end
end

config_file = "config.yaml"
config = Config.from_yaml File.read(config_file)
Log.info "Loaded config from #{config_file}"

Proxy.new(config).proxy
