require "./renderer"
require "./config"

module Login
  include Renderer

  def_render :login, "login.html", service : String
  def_render :invalid, "invalid.html", message : String
  def_render :services, "services.html", config : Config

  def authenticate_login(context) : {Symbol, String?}
    Log.debug "Logging in user"
    io = context.request.body
    return {:error, nil} unless io
    content = io.gets_to_end
    params = HTTP::Params.parse(content)
    username = params["username"]
    password = params["password"]
    return {:error, nil} unless username && password
    unless @users.login_user(username, password)
      return {:invalid, nil}
    end
    return {:ok, username}
  end

  def login(context, service)

  end
end
