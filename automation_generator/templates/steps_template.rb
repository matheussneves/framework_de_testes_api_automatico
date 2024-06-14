module Templates
  class StepsTemplate
    include CommonsTemplate

    attr_accessor :file_content, :file_path, :file_name, :endpoint, :data, :method, :main_var

    def initialize(file_path, file_name, data)
      self.main_var = 'endpoint'
      self.file_path = file_path
      self.file_name = file_name
      self.data = data

      splited_path = data.path.split('/')
      splited_path.shift
      splited_path = normalize_path(splited_path)
      self.endpoint = splited_path.join('_')

      create_file(file_path, file_name)
      self.file_content = load_file(file_path, file_name)
    end

    def build
      data.doc['paths'][data.endpoint].each_key do |method|
        self.method = method
        next unless file_content.match(/ #{endpoint}.#{method} /i).nil?

        build_steps
      end
    end

    def write
      if file_content == load_file(file_path, file_name)
        puts 'steps não foi gerado ou alterado'
      else
        update_file(file_path, file_name, file_content)
        puts 'steps foi gerado ou alterado'
      end
    end

    private

    def build_steps
      content = build_given
      content << build_when
      content << build_then

      file_content.insert(0, content)
    end

    def build_given
      path = data.doc['paths'][data.endpoint][method]

      %(Dado('ter uma massa configurada do endpoint #{endpoint}.#{method} para o cenário {tipo}') do |tipo|
  # Popular os parametros
  #{main_var} = OpenStruct.new
  #{main_var}.consumes = #{get_consumes_or_produces(path, 'consumes')}
  #{main_var}.produces = #{get_consumes_or_produces(path, 'produces')}
  #{build_all_params(main_var)}
  if tipo.eql?('negativo')
    # Criar logica para o cenario negativo
    #{main_var}.header = OpenStruct.new unless #{main_var}.header
    #{main_var}.header['fault'] = 'error_#{last_error_code}'
  end

  @#{endpoint}_#{method} = #{main_var}
end
\n)
    end

    def build_when
      direct = "@#{endpoint}_#{method}.response = #{endpoint}().#{method}_#{data.service_name}(@#{endpoint}_#{method})"

      integration_testing = %(if @integration_testing
  else
    #{direct}
  end)

      %(Quando('chamar o endpoint #{endpoint}.#{method}') do
  #{%w[post put].include?(method) ? integration_testing : direct}
rescue StandardError => error
  @#{endpoint}_#{method}.error = error
ensure
  puts(@#{endpoint}_#{method}.request_log, @#{endpoint}_#{method}.response_log)
end
\n)
    end

    def build_then
      success_response = build_response("#{main_var}.response.body")
      fault_response = build_response("#{main_var}.response.body", success: false)

      default = %(if tipo.eql?('positivo')
      expect(#{main_var}.error).to be_nil

#{success_response}
      # Fazer as validacoes necessarias para o cenario positivo
    else
#{fault_response}
      # Fazer as validacoes necessarias para o cenario negativo
    end)

      integration_testing = %(if @integration_testing
      if tipo.eql?('positivo')
        # Fazer as validacoes necessarias para o cenario positivo
      else
        expect(#{main_var}.error).not_to be_nil

        # Fazer as validacoes necessarias para o cenario negativo
      end
    elsif tipo.eql?('positivo')
      expect(#{main_var}.error).to be_nil

#{success_response}
      # Fazer as validacoes necessarias para o cenario positivo
    else
#{fault_response}
      # Fazer as validacoes necessarias para o cenario negativo
    end)

      %(Então('validar o retorno do endpoint #{endpoint}.#{method} para o cenário {tipo}') do |tipo|
  aggregate_failures do
    #{main_var} = @#{endpoint}_#{method}
    #{%w[post put].include?(method) ? integration_testing : default}
  end
end#{"\n" unless file_content.empty?}\n)
    end

    def build_all_params(main_var)
      var = "#{main_var}."
      "#{build_params(var, 'header')}#{build_params(var, 'formData')}#{build_params(var, 'body')}#{verify_base_path(var, build_params(var, 'path'))}#{build_params(var, 'query')}"
    end

    def build_params(variable, in_type)
      path = data.doc['paths'][data.endpoint][method]
      parameters = path['parameters']

      return nil if (parameters.nil? || parameters.none? { |item| item['in'].eql?(in_type) }) && !multipart_header?(path['consumes'], in_type)

      in_type_snake_case = snake_case(in_type)
      consumes = path['consumes']

      content = "\n  #{variable}#{in_type_snake_case} = OpenStruct.new\n"
      content << build_header_content_type(variable, in_type_snake_case, consumes, in_type)

      parameters.each do |item|
        next if item['in'] != in_type

        build_line(content, item, variable, in_type)
      end
      content
    end

    def verify_base_path(variable, path_params)
      vars = data.doc['basePath'].scan(/\{(\S+)\}/).flatten

      path_params ||= "\n  #{variable}path = OpenStruct.new\n"
      vars.each { |var| path_params << "  #{variable}path['#{var}'] = nil\n" }
      path_params
    end

    def multipart_header?(consumes, in_type)
      consumes && consumes.first.eql?('multipart/form-data') && in_type.eql?('header')
    end

    def build_header_content_type(variable, in_type_snake_case, consumes, in_type)
      content = ''
      content << "  #{variable}#{in_type_snake_case}['Content-Type'] = %(#{consumes.first})\n" if consumes && in_type.eql?('header')
      content
    end

    def build_line(content, item, var, in_type)
      variable = "  #{var}#{snake_case(in_type)}['#{item['name']}']"
      if item['schema']
        model = get_model(item)

        if item['schema']['type'].eql?('array') then build_array_model(content, [item['name'], item['schema']], "  #{var}#{snake_case(in_type)}")
        elsif model['type'].eql?('array') then build_array_model(content, [item['name'], model], "  #{var}#{snake_case(in_type)}")
        elsif model['allOf']
          content << "\n#{variable} = OpenStruct.new\n"
          build_composition_model(content, variable, model)
        else
          content << "\n#{variable} = OpenStruct.new\n"
          build_model(content, variable, model['properties'] || model['additionalProperties'])
        end
      else
        content << build_example_content(variable, item)
      end
    end

    def build_example_content(variable, item)
      "#{variable} = '#{item['example'] || item['x-example'] || item['type']}'\n"
    end

    def build_model(content, var, model)
      comment_swagger_error(var, content, 'model') unless model

      model.each do |item|
        variable = "#{var}['#{item.first}']"
        if item.last['$ref']
          content << "\n#{variable} = OpenStruct.new\n"
          sub_model = get_sub_model(item)
          sub_model['type'].eql?('string') ? set_variable_example(content, variable, sub_model) : build_model(content, variable, sub_model['properties'])
        elsif item.last['properties']
          content << "\n#{variable} = OpenStruct.new\n"
          build_model(content, variable, item.last['properties'])
        elsif item.last['type'].eql?('array') then build_array_model(content, item, variable)
        else
          set_variable_example(content, variable, item)
        end
      end
    end

    def build_array_model(content, item, variable)
      items = item.last['items']

      item_object = "  #{item.first}_item"
      content << "#{item_object} = OpenStruct.new\n" unless items['type'].eql?('string')

      if items['$ref']
        sub_model = get_sub_model(item)
        build_model(content, item_object, sub_model['properties'])
      elsif items['allOf'] || items['type'].eql?('object') then build_object_model(content, item_object, items)
      else
        set_variable_example(content, item_object, item)
      end

      set_array_variable_example(content, items, item, variable)
    end

    def build_object_model(content, var, model)
      content << "\n#{var} = OpenStruct.new\n" unless content.include?("#{var.strip} = OpenStruct.new")
      if model['allOf'] then build_composition_model(content, var, model)
      elsif model['type'].eql?('object') then build_model(content, var, model['properties'])
      else
        comment_swagger_error(model, content, 'object')
      end
      content << "#{var} = [#{var.strip}]\n"
    end

    def build_composition_model(content, var, model)
      model['allOf'].each do |item|
        if item['$ref']
          sub_model = get_sub_model(item)
          build_model(content, var, sub_model['properties'])
        elsif item['type'].eql?('object') then build_model(content, var, item['properties'])
        end
      end
    end

    def get_model(item)
      key = item['schema']['items'] ? item['schema']['items']['$ref'] : item['schema']['$ref']
      model = data.doc['definitions'][remove_prefix(key)]
      model = data.doc['definitions'][remove_prefix(model['$ref'])] if model['$ref']
      model
    end

    def get_sub_model(item)
      if item.instance_of?(Hash) && item['$ref'] then get_ref_definition(item['$ref'])
      elsif item.last['items'] then get_ref_definition(item.last['items']['$ref'])
      else
        get_ref_definition(item.last['$ref'])
      end
    end

    def get_ref_definition(ref)
      data.doc['definitions'][remove_prefix(ref)]
    end

    def remove_prefix(ref)
      item = ref.gsub('#/definitions/', '')
      /\A\d+\z/.match(item).nil? ? item : item.to_i
    end

    def get_example(item)
      item.is_a?(Array) ? item.last['example'] || item.last['x-example'] || item.last['type'] : item['example'] || item['x-example'] || item['type']
    end

    def set_variable_example(content, variable, item)
      value = get_example(item)
      content << "#{variable} = #{value.is_a?(String) ? "'#{value}'" : value}\n"
    end

    def set_array_variable_example(content, items, item, variable)
      content << if items['type'] != 'string' then content.include?(" = [#{item.first}_item]") ? "#{variable} = #{item.first}_item\n" : "#{variable} = [#{item.first}_item]\n"
                 elsif get_example(item).is_a?(Array) then "#{variable} = #{item.first}_item\n"
                 else
                   "#{variable} = [#{item.first}_item]\n"
                 end
    end

    def build_response(var, success: true)
      responses = data.doc['paths'][data.endpoint][method]['responses']

      content = ''
      responses.each_pair do |code, properties|
        unless properties['schema']
          puts "WARNING: structure '#{properties}' does not have schema..."
          next
        end

        if (success && code.to_i.between?(200, 299)) || (!success && code.to_i.between?(400, 599))
          walk_model(properties, content, var)
          break
        end
      end
      content
    end

    def walk_model(item, content, var)
      if item['schema']['$ref']
        model = get_model(item)

        if model['type'].eql?('array') then build_response_array_model(content, ['resp', model], "#{var}.first")
        elsif model['allOf'] then build_response_composition_model(content, var, model)
        else
          build_response_model(content, var, model['properties'])
        end
      elsif item['schema']['type'].eql?('array') then build_response_array_model(content, ['resp', item['schema']], "#{var}.first")
      else
        build_response_model(content, var, item['schema']['properties'])
      end
    end

    def build_response_model(content, var, model)
      return unless model

      model.each do |item|
        if item.last['$ref'] then build_response_ref_model(content, var, item)
        elsif item.last['properties'] then build_response_model(content, "#{var}['#{item.first}']", item.last['properties'])
        elsif item.last['type'].eql?('array') then build_response_array_model(content, item, "#{var}['#{item.first}'].first")
        else
          value = get_example(item)
          content << "      expect(#{var}['#{item.first}']).to eql(#{value.is_a?(String) ? "'#{value}'" : value})\n"
        end
      end
    end

    def build_response_composition_model(content, var, model)
      model['allOf'].each do |item|
        if item['$ref']
          sub_model = get_sub_model(item)
          build_response_model(content, var, sub_model['properties'])
        else
          build_response_model(content, var, item['properties'])
        end
      end
    end

    def build_response_ref_model(content, var, item)
      sub_model = get_sub_model(item)

      if sub_model['type'].eql?('array') then build_response_array_model(content, [item.first, sub_model], "#{var}['#{item.first}'].first")
      elsif sub_model['properties'] then build_response_model(content, "#{var}['#{item.first}']", sub_model['properties'])
      else
        value = get_example(sub_model)
        content << "      expect(#{var}['#{item.first}']).to eql(#{value.is_a?(String) ? "'#{value}'" : value})\n"
      end
    end

    def build_response_array_model(content, item, var)
      items = item.last['items']

      if items['$ref'] then build_response_sub_model(content, var, item)
      elsif items['type'].eql?('object') then build_response_model(content, var, items['properties'])
      elsif items['allOf'] then build_response_composition_model(content, var, items)
      else
        return content << "      expect(#{var}).to eql(#{get_array_example(item)}.first)\n" if item.last['example'] || item.last['x-example']

        content << "      expect(#{var}['#{item.first}']).to eql(#{get_array_example(item)})\n"
      end
    end

    def build_response_sub_model(content, var, item)
      model = get_sub_model(item)
      if model['allOf'] then build_response_composition_model(content, var, model)
      elsif model['properties'] then build_response_model(content, var, model['properties'])
      else
        comment_swagger_error(item, content, 'nested_object')
      end
    end

    def get_array_example(item)
      example = item.last['items']['example'] || item.last['items']['x-example'] || item.last['example'] || item.last['x-example'] || item.last['items']['type']
      Array(example)
    end

    def get_consumes_or_produces(path, type)
      value = path[type] || data.doc[type] || 'nil'

      value.is_a?(Array) ? %('#{value.first}') : value.to_s.tr('"', '\'')
    end

    def last_error_code
      data.doc['paths'][data.endpoint][method]['responses'].keys.last
    end
  end
end
