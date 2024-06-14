Dado('ter uma massa configurada do endpoint WM1_api_wm1_news.get para o cenário {tipo}') do |tipo|
  # Popular os parametros
  endpoint = OpenStruct.new
  endpoint.consumes = 'application/json'
  endpoint.produces = 'application/json'
  
  endpoint.path = OpenStruct.new

  if tipo.eql?('negativo')
    # Criar logica para o cenario negativo
    endpoint.header = OpenStruct.new unless endpoint.header
    endpoint.header['fault'] = 'error_400'
  end

  @WM1_api_wm1_news_get = endpoint
end

Quando('chamar o endpoint WM1_api_wm1_news.get') do
  @WM1_api_wm1_news_get.response = WM1_api_wm1_news().get_news(@WM1_api_wm1_news_get)
rescue StandardError => error
  @WM1_api_wm1_news_get.error = error
ensure
  puts(@WM1_api_wm1_news_get.request_log, @WM1_api_wm1_news_get.response_log)
end

Então('validar o retorno do endpoint WM1_api_wm1_news.get para o cenário {tipo}') do |tipo|
  aggregate_failures do
    endpoint = @WM1_api_wm1_news_get
    if tipo.eql?('positivo')
      expect(endpoint.error).to be_nil

      expect(endpoint.response.body.first['AutorId']).to eql(253)
      expect(endpoint.response.body.first['Content']).to eql('Em anúncio feito nesta semana, o CEO da Stellantis, Carlos Tavarez, confirmou que a montadora italiana pretende trazer o subcompacto tradicional em versão híbrida leve.')
      expect(endpoint.response.body.first['CategoriaSlug']).to eql('noticias')
      expect(endpoint.response.body.first['IdImage']).to eql(801028)
      expect(endpoint.response.body.first['Titulo']).to eql('Fiat 500 terá versão híbrida, mas vai demorar')
      expect(endpoint.response.body.first['Categoria']).to eql('Últimas notícias')
      expect(endpoint.response.body.first['Autor']).to eql('Lucas Cardoso')
      expect(endpoint.response.body.first['Url']).to eql('https://www.webmotors.com.br/wm1/noticias/fiat-500-tera-versao-hibrida-mas-vai-demorar')
      expect(endpoint.response.body.first['UrlPrincipalImage']).to eql('https://www.webmotors.com.br/wp-content/uploads/2024/06/07175328/500-hibrido-F2-730x545.webp')
      expect(endpoint.response.body.first['AutorAvatar']).to eql('https://www.webmotors.com.br/wm1/assets/508d6137c5695b5ed13ab89101f9d24d.png')

      # Fazer as validacoes necessarias para o cenario positivo
    else

      # Fazer as validacoes necessarias para o cenario negativo
    end
  end
end
