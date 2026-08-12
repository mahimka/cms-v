require_relative './environment'

# Ancestry.default_ancestry_format = :materialized_path2

if ActiveRecord::Base.connection.migration_context.needs_migration?
  raise 'Migrations are pending. Run `rake db:migrate` to resolve the issue.'
end


#In order to send HTTP PATCH and DELETE requests, I need to add Sinatra middleware. 
use Rack::MethodOverride 

# порядок имеет значение!!
use AdminController
use ProfilesController
use SitesController
use SnapShotsController
use MarkersController
use TagsController
use SchemasController
use LabelsController
use LinksController
use DetailsController
use PicturesController
use ItemsController
use EntitiesController
use EventsController
use PagesController
use HistoriesController

use RoutesFirst
use Routes
use RoutesLast


# use GeonamesController
# use AdsController


# use ProfilesController
# use TagsController
# use AdsController

# use ProjectMethods
# use RssRoutesController
# use SitemapRoutesController
# use RoutesController
# use DisplayController


run App

