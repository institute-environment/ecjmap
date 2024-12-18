

# Description -------------------------------------------------------------

#' This script cleans/processes data related to climate/climate change. Right
#' now this only includes burn probability but we may add heat risk and forest
#' thinning in the future future. We are not currently using the FHSZ data 
#' because it only estimates fire risk for public lands.
#' 
#' Burn Probability: https://caregionalresourcekits.org/statewide.html
#' FHSZ Data: https://data.ca.gov/dataset/fire-hazard-severity-zones-in-sra-effective-april-1-2024-with-lra-recommended-2007-2011/resource/d22132ba-3c1b-4b34-bb47-ab1c89e7d2f8
#' Forest Thinning: https://calfire-forestry.maps.arcgis.com/home/item.html?id=80d439247b99489a938b09a0d182173c
#' Climate Disaster Risk: https://hazards.fema.gov/nri/map
#' Heat: https://www.cal-heat.org/download

library('sf')
library('httr')
library('geojsonsf')
library('terra')
library('tigris')

options(tigris_use_cache = TRUE)

source('R/functions.R')
#write_sf()
#Mode()



# Functions ---------------------------------------------------------------

#' Convert probability over one time interval to probability over a different
#' time interval
#' 
#' original_p   numeric vector, probabilities of a given thing happening during
#'                a given time interval
#' new_int      numeric, time interval the new probability should be calculated
#'                for.
#' old_int      numeric, time interval over which the original probability was
#'                calculated
#' 
#' Returns a probability of something happening over a different time interval.
#' For example, if you had the annual probability of being in a car accident (p)
#' but wanted the lifetime probability of being in a car accident you would use
#' `convert_prob(p, 75, 1)` assuming you live for 75 years.
#' 
convert_prob = function(original_p, new_int, old_int=1) {
  
  new_p = 1 - (1-original_p)^(new_int/old_int)
  
  return(new_p)
}


# Create Tract/Block vectors ----------------------------------------------

#get census geographies (census tracts and block groups)
tract = tracts(state='CA')
bg = block_groups(state='CA')
#bk = blocks(state='CA')
#names(bk) = gsub('20', '', names(bk))

#extract tract id from tract and block group ids
tract$tract_id = tract$GEOID
bg$tract_id = substr(bg$GEOID, 1, 11)
#bk$tract_id = substr(bk$GEOID, 1, 11)


#determine which tracts are too big to be aggregatecd across
large_tract_size = quantile(tract$ALAND, 0.99)

voi = c('GEOID', 'tract_id', 'geometry', 'ALAND')

#remove large tracts
small_tracts = tract[tract$ALAND < large_tract_size, voi]

#select only block groups that correspond to the large tracts.
large_bgs = bg[!bg$tract_id %in% small_tracts$tract_id, voi]

#Select blocks that correspond to large block groups 
#large_bg_size = quantile(large_bgs$ALAND, 0.90)
#small_bgs = large_bgs[large_bgs$ALAND > large_bg_size, ]
#large_bks = bk[!bk$tract_id %in% small_tracts$tract_id, voi]


#combine small tracts and block groups from large tracts
polys = rbind(small_tracts, large_bgs)
#polys = rbind(small_tracts, small_bgs, large_bks)

#convert to california albers projection because that is what the raster is in
ca_polys = st_transform(polys, 3310)


# Burn Probability --------------------------------------------------------

#name of layer and folder layer is in
slug = 'AnnualBurnProbability2022'

#file name 
fn = paste0('data/raw/', slug, '/', slug, '.tif')

#read in annual burn probability raster for california
annual_prob = rast(fn)

#convert annual burn probability to probability of burn over 10 years, ~3 mins
#takes 2-3 minutes
prob_10 <- sapply(annual_prob, convert_prob, new_int=10)[[1]]

#get the max burn probability for each census geography
#~20 minutes for block groups, ~ 40 mins for blocks
system.time(prob_10_poly <- extract(prob_10, vect(ca_polys), fun=max, na.rm=TRUE, bind=TRUE))
#system.time(prob_10_poly_mean <- extract(prob_10, vect(ca_polys), fun=mean, na.rm=TRUE, bind=TRUE))
#system.time(prob_10_poly_med <- extract(prob_10, vect(ca_polys), fun=quantile, probs=0.5, na.rm=TRUE, bind=TRUE))

#round to 4 decimal places
prob_10_poly$burn_prob = round(prob_10_poly$AnnualBurnProbability2022, 4)

#removing geographies with negligible file risk
prob_10_high = prob_10_poly[prob_10_poly$burn_prob>0.20, c('GEOID', 'tract_id', 'burn_prob')]

#reproject geographies to lat/long which is what the web map is in
prob_10_high = project(prob_10_high, 'epsg:4326')

#write data
writeVector(prob_10_high, 'data/final/burn_probability_10yrs.geojson', 
            filetype='GeoJSON', overwrite=TRUE)


# fire hazard -------------------------------------------------------------

#API URL
fire_url = 'https://gis.data.cnra.ca.gov/api/download/v1/items/ac8ed44d76ed4988bceb07d35d80f4cb/geojson?layers=0'

#response from the API decoded
fire_api_response = GET(fire_url)$content |> rawToChar() 

#converting response to sf object
fire = geojson_sf(fire_api_response)

#making geometry valid
fire = st_make_valid(fire)

#Make who is responsible more clear
fire$Responsibility = ifelse(fire$SRA22_2=='SRA', 'State', 'Local')

#selecting oly variables we care about
fire_ca = fire[, c('Responsibility', 'FHSZ', 'FHSZ_Description')]

#how we are aggregating the polygons
fh_agg_by = list(fire_ca$Responsibility, fire_ca$FHSZ_Description)

#aggregating the polygons
fire_ca_agg = aggregate(fire_ca, FUN=Mode, by=fh_agg_by) |>
  st_make_valid()

fire_ca_agg = fire_ca_agg[, c('Responsibility', 'FHSZ', 'FHSZ_Description')]

fire_buff5 = 

#seeing how much we need to compress the size of the object
object.size(fire_ca_agg) |> format(units='auto')

#simplifying geometries which will make the object size smaller
fire_ca_agg_simpl = st_simplify(fire_ca_agg, TRUE, 35)

object.size(fire_ca_agg_simpl) |> format(units='auto')

#saving the data
write_sf(fire_ca_agg, 'data/clean/fire_risk.geojson')



