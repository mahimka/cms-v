class LostUrlsController < App

  namespace '/admin' do

    get '/lost_urls' do
      @q = LostUrl.ransack(params[:q])
      @lost_urls_found = @q.result(distinct: true)
      @lost_urls = @q.result(distinct: true).order(hits_count: :desc).page(params[:page]).per(100)

      erb :"/lost_urls/index", layout: :"/layout/wide", views: settings.views_admin
    end

    # Разобрать log/lost_urls.log (см. LostUrlLogger) и upsert'ить в
    # таблицу — по кнопке на /admin/lost_urls, не автоматически.
    post '/lost_urls/import' do
      result = LostUrl.import_from_log!
      flash[:notice] = "Imported: #{result[:imported]} unique path(s) from #{result[:rows]} log line(s)"
      redirect '/admin/lost_urls'
    end

    post '/lost_urls/:id/mark_reviewed' do
      lost_url = LostUrl.find(params[:id])
      lost_url.update!(reviewed: true)
      redirect back
    end

    delete '/lost_urls/:id' do
      LostUrl.find(params[:id]).destroy
      redirect '/admin/lost_urls'
    end

  end

end
