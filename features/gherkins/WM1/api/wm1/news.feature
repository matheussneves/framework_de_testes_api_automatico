# language:pt

@api
@id_epico_jira???
@id_estoria_jira???
@WM1_api_wm1_news
Funcionalidade: WM1 | api - Validar o endpoint news
  Como uma aplicação de APIs
  Quero chamar o endpoint da API
  Para validar a funcionalidade do mesmo

  @#nome_responsavel???
  @id_epico_jira???
  @id_estoria_jira???
  @id_task_jira???
  @WM1_api_wm1_news.get
  Esquema do Cenário: Validar o endpoint WM1_api_wm1_news.get
    Dado ter uma massa configurada do endpoint WM1_api_wm1_news.get para o cenário <tipo>
    Quando chamar o endpoint WM1_api_wm1_news.get
    Então validar o retorno do endpoint WM1_api_wm1_news.get para o cenário <tipo>

    @ingress_testing
    Exemplos:
      | tipo     |
      | positivo |
      | negativo |
