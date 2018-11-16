require "logger"

class Log
  @@logger = Logger.new(STDOUT)

  def self.set_logger(logger)
    @@logger = logger
  end

  def self.log(severity, message)
    @@logger.log(severity, message)
  end

  {% for method in {:log, :warn, :info, :debug, :error, :fatal, :unknown} %}
    def self.{{ method.id }}(*args)
      @@logger.{{ method.id }}(*args)
    end
  {% end %}
end
