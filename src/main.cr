require "http/server"
require "http/client"
require "uuid"

COOKIE_NAME = "cr-proxy-token"

class Proxy
  @tokens = Hash(String, Time).new

  @services = {
    "crometheus" => {"127.0.0.1", 5000}
  } of String => {String, Int32}

  def initialize
    @tokens["1234"] = Time.now
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
    valid_until = @tokens[token]?
    puts valid_until
    return :invalid unless valid_until
    # TODO check valid time
    :ok
  end

  def respond_authentication(context, status)
    context.response.status_code = 401
    context.response.print {{ `cat templates/login.html`.stringify }}
  end

  def login_and_respond(context)
    id = UUID.random.to_s
    @tokens[id] = Time.now
    context.response.status_code = 200
    context.response.headers.add(
      "Set-Cookie", "#{COOKIE_NAME}=#{id};"
    )
    context.response.print "Logged in!"
  end

  def proxy(host, port)
    server = HTTP::Server.new do |context|
      path = context.request.path
      end_idx = path.byte_index('/'.ord, 1)
      if end_idx
        service = path[1...end_idx]
        proxy_path = path[end_idx...-1]
      else
        service = path[1..-1]
        proxy_path = "/"
      end
      if service == "login"
        puts "Logging in"
        login_and_respond(context)
        next
      end
      found = @services[service]?
      puts "#{service} #{found} - #{proxy_path}"
      auth_status = check_authentication(context.request.headers)
      if auth_status != :ok
        puts "Authentication failed: #{auth_status}"
        respond_authentication(context, auth_status)
        next
      end
      unless found
        puts "No host found"
        next
      end
      host, port = found
      client = HTTP::Client.new host, port: port
      response = client.get proxy_path
      context.response.status_code = response.status_code
      context.response.headers.merge! response.headers
      context.response.print response.body
      client.close
    end

    server.bind_tcp host, port
    puts "Proxying on http://#{host}:#{port}"
    server.listen
  end
end

Proxy.new.proxy "0.0.0.0", 8080
