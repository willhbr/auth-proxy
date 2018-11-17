require "http/server"
require "http/client"
require "uuid"

require "./config"
require "./logger"
require "./users"
require "./login"

COOKIE_NAME = "cr-proxy-token"

class Proxy
  include Login
  @config : Config
  @server : HTTP::Server? = nil

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
    Log.debug "Login using #{token}, token valid? #{is_valid}"
    return :invalid unless is_valid
    :ok
  end

  def login_and_respond(context)
    Log.debug("Attempting login")
    status, username = authenticate_login(context)
    if status == :ok && username
      id = @users.make_token_for(username, 2.days.from_now)
      context.response.status_code = 200
      context.response.headers.add(
        "Set-Cookie", "#{COOKIE_NAME}=#{id};"
      )
      Log.info("Login successful: #{username}")
      render_services(context, @config)
      return
    end
    render_invalid(context, "Authentication failed")
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
    @server = server = HTTP::Server.new do |context|
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
        render_login(context, service)
        next
      end
      unless found
        Log.info "No host found for #{service}"
        render_invalid(context, "Service doesn't exist: #{service}")
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

  def save_tokens
    @users.save(@config.password_file)
  end

  def stop
    if server = @server
      Log.info "Stopping server"
      server.close
    end
  end
end

config_file = "config.yaml"
config = Config.from_yaml File.read(config_file)
Log.info "Loaded config from #{config_file}"

proxy = Proxy.new(config)
Signal::INT.trap do
  Log.info "Interrupted!"
  proxy.save_tokens
  proxy.stop
end
proxy.proxy()

