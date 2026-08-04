module PageTreeHelpers

  # Возвращает массив:
  #
  # [
  #   { page: page, has_children: true },
  #   { page: page, has_children: false }
  # ]
  #
  # Проверка наличия детей выполняется одним дополнительным запросом,
  # а не отдельным запросом для каждой страницы.
  def prepare_tree_rows(pages)
    pages.map do |page|
      {
        page: page,
        has_children: page.children.exists?
      }
    end
  end


end