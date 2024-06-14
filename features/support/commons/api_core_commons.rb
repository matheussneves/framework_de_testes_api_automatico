module ApiCommons
  def call_validate_api(connection, package, params)
    response = nil
    begin
      if EXCON_LOG
        request_log(connection, package, params)
        params.start_time = Time.now
      end

      produces = params.produces.to_s
      build_sse_block(package, produces)
      response = execute_request(connection, package)
      parse_response_body(response, produces, connection, package)
    ensure
      if EXCON_LOG
        params.finish_time = Time.now
        response_log(connection, package, params, response)
      end
    end
    response
  end

  def build_package(method_name, class_name, params)
    params.class_name = class_name

    package = OpenStruct.new
    package.method = get_api_method(method_name)
    package.path = get_api_path(class_name, params)
    package.body = build_body(params)
    package.params = params.query.to_h
    package.query = build_query(params)
    package.headers = clear_hash(params.header.to_h)
    clear_hash(package.to_h)
  end

  def get_new_connection(base_uri, headers)
    if headers.value?('multipart/form-data')
      Faraday.new(url: base_uri, headers: headers) do |conn|
        conn.request :multipart
        conn.response :json, parser_options: { object_class: Hash }
        conn.adapter :net_http
      end
    else
      Excon.new(base_uri, headers: headers)
    end
  end

  def build_body(params)
    return unless params.body || params.form_data

    body = normalize_body(params)

    hash = body_to_hash(body)

    consumes = params.consumes.to_s
    if consumes.include?('application/x-www-form-urlencoded')
      URI.encode_www_form(hash)
    elsif consumes.include?('multipart/form-data')
      hash
    else
      hash.to_json
    end
  end

  def normalize_body(params)
    if params.body
      if params.body.is_a?(Array)
        params.body
      else
        params.body.to_h.values.first
      end
    else
      params.form_data
    end
  end

  def get_base_uri(api_name)
    caller = caller_locations(1, 1).first.label
    API_CONFIG['urls'][api_name]

  end

  def get_multipart_file(file_path)
    Faraday::UploadIO.new(file_path, MIME::Types.type_for(file_path).first.content_type)
  end

  def parse_json_to_xml(json)
    Nokogiri::XML(json)
  end

  private

  def execute_request(connection, package)
    if connection.is_a?(Faraday::Connection)
      call_faraday_request(connection, package)
    else
      package[:path] = connection.data[:path] + package[:path]
      connection.request(package)
    end
  end

  def call_faraday_request(connection, package)
    connection.method(package[:method].downcase).call(package[:path]) do |request|
      request.params = package[:params]
      request.body = package[:body] unless package[:body].empty?
    end
  end

  def body_to_hash(body)
    if body.is_a?(Array)
      body.map! do |item|
        openstruct_to_hash(item)
      end
    else
      openstruct_to_hash(body)
    end
  end

  def openstruct_to_hash(object, hash = {})
    return object if object.is_a?(String) || object.is_a?(Array) || object.is_a?(Integer)

    object.each_pair do |key, value|
      hash[key] = case value
                  when OpenStruct
                    openstruct_to_hash(value)
                  when Array
                    value.map! do |item|
                      openstruct_to_hash(item)
                    end
                  else
                    value
                  end
    end
    clear_hash(hash)
  end

  def build_query(params)
    return unless params.query

    params.query.each_pair do |key, value|
      params.query[key] = value.join(',') if value.is_a?(Array)
    end

    URI.encode_www_form(clear_hash(params.query.to_h))
  end

  def get_api_method(method_name)
    method_name.to_s.split('_').first.to_sym
  end

  def get_api_path(clazz, params, skip_replace: false)
    class_name = clazz.gsub('Class', '').split('::')
    class_name.shift

    class_name = class_name.map do |name|
      name = decode_patterns(name)
      new_name = case name
                 when 'Partners-partnerCode' then "partners-#{params.path['partnerCode']}"
                 when 'Partners-partnerCode-loyalty' then "partners-#{params.path['partnerCode']}-loyalty"
                 when 'Partner-catalog-partnerCode' then "partner-catalog-#{params.path['partnerCode']}"
                 when 'Partners-partnerCode-connector' then "partners-#{params.path['partnerCode']}-connector"
                 else first_downcase(name)
                 end
      skip_replace ? new_name : (params.path && params.path[new_name]) || new_name
    end
    "/#{class_name.join('/')}"
  end

  def decode_patterns(str)
    str.gsub('_h_', '-').gsub('_d_', '.').gsub('_loyalty', '-loyalty')
  end

  def clear_hash(hash)
    hash.compact
  end

  def first_downcase(str)
    str[0, 1].downcase + str[1..]
  end

  def valid_json?(json)
    JSON.parse(json)
    true
  rescue JSON::ParserError
    false
  end

  def build_sse_block(package, produces)
    return unless produces.include?('text/event-stream')

    package[:sse_data] = ''
    package[:response_block] = ->(data, _remaining, _total) { package[:sse_data] += data.to_s } if produces.include?('text/event-stream')
  end

  def parse_response_body(response, produces, connection, package)
    response.body = package[:sse_data].delete_prefix('data:') if produces.include?('text/event-stream')
    response.body = JSON.parse(response.body) unless connection.is_a?(Faraday::Connection) || response.body.empty? || !valid_json?(response.body) || !['application/json', 'text/event-stream'].include?(produces)
  end
end
