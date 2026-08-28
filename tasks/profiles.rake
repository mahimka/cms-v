namespace :profiles do
  desc "Синхронизировать title/h1/meta_description/rating/review_count/scraped_at из последнего SnapShot (rake profiles:sync_from_snap_shots)"
  task :sync_from_snap_shots do
    profile_ids = SnapShot.distinct.pluck(:profile_id).compact

    puts "Найдено #{profile_ids.size} profile(ей) со snap_shot"

    profile_ids.each do |profile_id|
      profile = Profile.find_by(id: profile_id)
      next unless profile

      snap_shot = profile.snap_shots.order(created_at: :desc).first
      next unless snap_shot

      profile.title = snap_shot.title
      profile.h1 = snap_shot.h1
      profile.meta_description = snap_shot.meta_description
      profile.scraped_at = snap_shot.created_at

      rating = SnapShotParser.parse_rating(profile.details && profile.details['rating'])
      profile.rating = rating if rating

      review_count = SnapShotParser.parse_review_count(profile.details && profile.details['review_count'])
      profile.review_count = review_count if review_count

      profile.save!

      puts "##{profile.id}: OK (snap_shot ##{snap_shot.id})"
    end
  end
end
