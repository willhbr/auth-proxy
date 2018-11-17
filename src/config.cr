require "yaml"

class Config
  YAML.mapping(
    base_url: String,
    host: String,
    port: Int32,
    services: Array(Service),
    password_file: String,
  )

  class Service
    YAML.mapping(
      name: String,
      port: Int32,
      host: {
        type: String,
        default: "127.0.0.1"
      }
    )
  end

  def get_host_and_port(name) : {String, Int32}?
    service = @services.find { |s| s.name == name }
    return nil unless service
    return service.host, service.port
  end
end
