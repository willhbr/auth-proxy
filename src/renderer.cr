require "./logger"
require "ecr"

module Renderer
  macro def_render(name, ecr_file, *args)
    class Renderer_{{ name.id }}
      def initialize(
        {% for arg in args %}
          @{{ arg }},
        {% end %})
      end

      ECR.def_to_s("templates/#{ {{ ecr_file }} }.ecr")
    end
    def render_{{ name.id }}(context, *args)
      Log.info("Rendering #{ {{ ecr_file }} }")
      Renderer_{{ name.id }}.new(*args).to_s(context.response)
    end
  end
end
