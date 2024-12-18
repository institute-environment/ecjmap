

# Description -------------------------------------------------------------

#' This script downloads and processes data about Indigenous people and land 
#' of California. It draws on both census data and the Native Land project data
#' (https://native-land.ca/).
#' 

survey_year = 2022
survey = 'acs/acs5'


# Setup -------------------------------------------------------------------

library('sf')
library('tigris')
library('data.table')
library('tidycensus')
library('httr')
library('jsonlite')
library('geojsonsf')

source('R/functions_census.R')


options(tigris_use_cache = TRUE)

#extract survey name from survey path
survey_name = strsplit(survey, '\\/')[[1]][2]




# Is Invalid LatLong ------------------------------------------------------

is_valid_latlong = function(geom) {
  coords = st_coordinates(geom)[,c('X', 'Y')]
  
  is_valid_ll = all(coords < 180 & coords > -180)
  
  return(is_valid_ll)
  
} 

# Read in non census data -------------------------------------------------

#read in data dictionary for the survey
dd_fn = create_dd_fn('data/clean/census', survey_name, survey_year, is_split=TRUE)

dd = read.csv(dd_fn)
setDT(dd)

# california outline
ca = st_read('data/clean/california.geojson')


# Get API key -------------------------------------------------------------

# load the API key from a local file
con<-file("census_API_key.txt")
api_key<-readLines(con)
close(con)


# Federally recognized Tribal Lands ---------------------------------------

tribal = native_areas(year = survey_year)
names(tribal) = tolower(names(tribal))

#classify tribal land as either a reservati
tribal$land_type = ifelse(tribal$comptyp=='R', 'Reservation', 'Trust Land')

tribal_wgs = st_transform(tribal, st_crs(ca))

tribal_ca = filter_to_boundary(tribal_wgs, ca)

tribal_ca = tribal_ca[,c('geoid', 'name', 'land_type', 'geometry')]

tribal_ca$source = 'federal'

write_sf(tribal_ca, 'data/final/tribal_areas.geojson')

tribal_boundary = st_cast(tribal_ca, 'MULTILINESTRING') |> st_sf()
st_geometry(tribal_boundary) <- 'geometry'

tribal_boundary$source = 'federal'

write_sf(tribal_boundary, 'data/final/tribal_boundary.geojson')


# High Population Indigenous Tracts ---------------------------------------
#This uses anyone who identifies as American Indian and Alaska Native even if
#they also identify as another race as well


aian = import_census('tract', survey_name, survey_year, TRUE, 
                      api_key, dd, table='B02010')

#aian$l_pop = aian$estimate - aian$moe

pop90 = quantile(aian$estimate, 0.9, na.rm=TRUE)
#l_pop95 = quantile(aian$l_pop, 0.9, na.rm=TRUE)

aian_pop = aian[aian$estimate>pop90, ]
#aian_lpop = aian[aian$l_pop>l_pop95, ]

plot_feature(aian_pop, 'variable')

aian_pop_union = st_union(aian_pop) |> st_sf()
st_geometry(aian_pop_union) <- 'geometry'

aian_pop_union$source = 'census_highpop'

write_sf(aian_pop_union, 'data/final/native_tracts_highpop.geojson')


aian_pop_boundary = st_cast(aian_pop_union, 'MULTILINESTRING') |> st_sf()
st_geometry(aian_pop_boundary) <- 'geometry'

aian_pop_boundary$source = 'census_highpop'


write_sf(aian_pop_boundary, 
         'data/final/native_boundary_highpop.geojson')


# High Population Indigenous Only Tracts ----------------------------------
#this only counts people who only identify as American Indian and Alaska Native

race = import_census('tract', survey_name, survey_year, TRUE, 
                     api_key, dd, table='B02001')


aian_only = race[aian_only$label3=='American Indian and Alaska Native alone' &
                   !is.na(aian_only$label3),]

pop90_only = quantile(aian_only$estimate, 0.9, na.rm=TRUE)

aian_pop_only = aian_only[aian_only$estimate>pop90_only, ]

plot_feature(aian_pop_only, 'variable')



# Native Lands ------------------------------------------------------------
#' Some of the native lands circumnavigate the globe and include lat/lon 
#' values that are greater than 180 so you need to go into QGIS and delete 
#' the those geometries manually.

native_land_api_call = 'https://native-land.ca/api/index.php?maps=territories'

api_response = GET(native_land_api_call)$content |> rawToChar()
native_world0 = geojson_sf(api_response)
native_world1 = st_zm(native_world0)

has_valid_latlong = sapply(native_world1$geometry, is_valid_latlong)
native_world2 = native_world1[has_valid_latlong, ]

native_world = st_make_valid(native_world2)

write_sf(native_world, 'data/native_lands.geojson') 

#open in QGIS, delete horizontal bar polygons, fix geometries, select polygons 
#that overlap with California and write to data/clean/native_lands_ca.geojson

native_ca = st_read('data/clean/native_lands_ca.geojson')

native_ca$area = st_area(native_ca)
native_ca$plot_order = order(native_ca$area, decreasing=TRUE)
native_ca$area = NULL

write_sf(native_ca, 'data/clean/native_lands_ca.geojson')
