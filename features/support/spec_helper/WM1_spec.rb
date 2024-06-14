def WM1_api_wm1_news
  WM1::Api::Wm1::NewsClass.new(get_base_uri('WM1'))
end
