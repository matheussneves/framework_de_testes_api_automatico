module WM1
  module Api
    module Wm1
      class NewsClass
        include ApiCommons

        attr_accessor :base_uri

        def get_news(params)
          connection = get_new_connection(base_uri, params.header.to_h)
          package = build_package(__method__, self.class.name, params)

          call_validate_api(connection, package, params)
        end

        def initialize(base_uri)
          self.base_uri = base_uri
        end
      end
    end
  end
end

World(WM1::Api::Wm1)
