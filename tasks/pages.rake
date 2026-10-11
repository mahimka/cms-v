namespace :pages do
  desc "Публикует 1-2 случайные готовые страницы (ready: true, published: false) вместе с картинками. Не больше per_day=10 за календарный день (rake pages:publish_ready [per_day=10] [max=2])"
  task :publish_ready do
    per_day = (ENV['per_day'] || 10).to_i
    max     = (ENV['max'] || 2).to_i

    # Отдельного published_at нет — считаем опубликованные сегодня по updated_at.
    # Приблизительно (правка уже опубликованной страницы тоже сдвигает updated_at),
    # но для лимита "около 10 в день" этого достаточно.
    done_today = Page.where(published: true, updated_at: Time.now.beginning_of_day..).count
    limit      = [rand(1..max), per_day - done_today].min

    if limit <= 0
      puts "Лимит #{per_day} страниц в день исчерпан"
      next
    end

    Page.where(ready: true, published: false).order(Arel.sql("RANDOM()")).limit(limit).each do |page|
      unless page.update(published: true)
        puts "#{page.uri}: не сохранилась — #{page.errors.full_messages.join(', ')}"
        next
      end

      pictures = page.pageable&.respond_to?(:pictures) ? page.pageable.pictures.where(active: true, published: false) : Picture.none
      count    = pictures.update_all(published: true, updated_at: Time.now)

      puts "#{page.uri}: опубликована, картинок: #{count}"
    end
  end
end
