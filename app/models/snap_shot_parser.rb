class SnapShotParser

  PROMPTS_DIR = File.expand_path('../../project/prompts', __dir__)

  # "4.5", "4,5", "4.5 out of 5", "4.5/5" -> 4.5. nil, если чисел вообще нет.
  # Публичный class method — переиспользуется tasks/profiles.rake, чтобы не
  # дублировать разбор строки при пересборке profile.rating из details.
  def self.parse_rating(value)
    return nil if value.blank?

    match = value.to_s.match(/(\d+[.,]?\d*)/)
    match ? match[1].tr(',', '.').to_f : nil
  end

  # "230", "1,234", "1234 reviews" -> integer. nil, если цифр вообще нет.
  def self.parse_review_count(value)
    return nil if value.blank?

    digits = value.to_s.gsub(/[^\d]/, '')
    digits.empty? ? nil : digits.to_i
  end

  def initialize(client:)
    @client = client
  end

  # Один SnapShot: подбирает промпт по site+schema профиля, вызывает
  # client.extract_profile_data, создаёт/находит Marker'ы, доливает
  # profile.details, помечает snap_shot как parsed.
  def parse!(snap_shot)
    profile = snap_shot.profile
    return { success: false, error: 'snap_shot без profile' } unless profile

    prompt_path = resolve_prompt_path(profile)
    instructions = File.read(prompt_path)

    data = @client.extract_profile_data(snap_shot.html_content, instructions: instructions)

    apply_markers(profile, data['markers'])
    apply_details(profile, data['details'])

    snap_shot.update!(parsed: true, parsed_at: Time.now)

    { success: true, prompt: File.basename(prompt_path), markers: data['markers'], details: data['details'] }
  rescue => e
    { success: false, error: "#{e.class}: #{e.message}" }
  end

  private

  # site.domain + schema объекта (Restaurant/Hotel/...) -> имя файла, с
  # фоллбеком на промпт для всего сайта, а дальше на общий default.txt.
  def resolve_prompt_path(profile)
    domain = profile.site&.domain
    profileable = profile.profileable
    schema_name = profileable.respond_to?(:schema) ? profileable.schema&.name : nil

    candidates = [
      (domain && schema_name) ? "#{domain}_#{schema_name.downcase}.txt" : nil,
      domain ? "#{domain}.txt" : nil,
      "default.txt"
    ].compact

    candidates.each do |filename|
      path = File.join(PROMPTS_DIR, filename)
      return path if File.exist?(path)
    end

    File.join(PROMPTS_DIR, "default.txt")
  end

  def apply_markers(profile, markers)
    return if markers.blank?

    markers.each do |group, values|
      Array(values).each do |value|
        next if value.to_s.strip.empty?

        marker = Marker.where(group: group, name: value.to_s[0, 240], site_id: profile.site_id).first_or_create
        ProfileMarker.where(marker_id: marker.id, profile_id: profile.id).first_or_create
      end
    end
  end

  def apply_details(profile, details)
    return if details.blank?

    profile.details = (profile.details || {}).merge(details)

    # rating/review_count дублируются из details в типизированные колонки —
    # они на горячем пути отображения (ссылки на профили с др. сайтов в
    # обзоре объекта), сортировать/форматировать из сериализованного JSON
    # неудобно. details остаётся полным сырым слепком того, что извлёк AI.
    rating = self.class.parse_rating(details['rating'])
    profile.rating = rating if rating

    review_count = self.class.parse_review_count(details['review_count'])
    profile.review_count = review_count if review_count

    profile.save!
  end

end
