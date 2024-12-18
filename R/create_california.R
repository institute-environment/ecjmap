

# Description -------------------------------------------------------------

#' This script downloads the census polygons for the counties of California 
#' using the tigris package. It merges them to create a single polygon for 
#' the state of California. Next it merges the counties by their CA Jobs First
#' Economic Regions and creates polylines out of each of them. Finally it 
#' selects the north state boundary line into a separate object. It writes all 
#' of these objects to .geojsons for later use.


# Setup -------------------------------------------------------------------


library('sf')
library('dplyr')
library('tigris')

source('R/functions.R')

options(tigris_use_cache = TRUE)


#North State Counties
regions_df = read.csv('data/raw/ca-jobs-first_regions.csv')



# Download County Geographies ---------------------------------------------

#California Counties
ca_counties = counties(state='06')
names(ca_counties) = tolower(names(ca_counties))

ca_counties = st_transform(ca_counties, 3310)

ca_counties = merge(ca_counties, regions_df, by='name')

# Create California Polygon -----------------------------------------------

ca = st_union(ca_counties)

ca = st_transform(ca, 4326)

write_sf(ca, 'data/clean/california.geojson')



# Create Region Boundaries ------------------------------------------------

regions = ca_counties |>
  group_by(region) |>
  summarize(geometry = st_union(geometry)) |>
  ungroup() |>
  st_make_valid()

regions_boundary = st_cast(regions, 'MULTILINESTRING')

regions_boundary = st_transform(regions_boundary, 4326)

write_sf(regions_boundary, 'data/final/ca-jobs-first_regions.geojson')

# Create North State Boundary ---------------------------------------------

north_state_boundary = regions_boundary[regions_boundary$region=='North State', ]

write_sf(north_state_boundary, 'data/final/north_state_region.geojson')


