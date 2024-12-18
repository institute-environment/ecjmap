
# Description -------------------------------------------------------------

#' This script downloads data from the US Census using the tidycensus package
#' and labels the variables with human readable names (drawn from file created
#' by R/create_census_var_table.R). Run that first if you haven't already for
#' the survey you are interested in. Make sure variables below match the
#' variables you set at the top of that script.

survey_year = 2022
survey = 'acs/acs5'

# Setup -------------------------------------------------------------------

library('sf')
library('tigris')
library('tidycensus')
library('data.table')
library('stringr')
box::use(dplyr = dplyr[case_when])

source('R/functions_census.R')
source('R/functions.R')


options(tigris_use_cache = TRUE)

#extract survey name from survey path
survey_name = strsplit(survey, '\\/')[[1]][2]

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



# Get Geometry ------------------------------------------------------------

tract0 = tracts(state='CA', year = survey_year)
tract = format_census_geom(tract0)

bg0 = block_groups(state='CA', year = survey_year)
bg = format_census_geom(bg0)

# Get Race Data -----------------------------------------------------------

# #25607 block groups
# race = import_census('tract', survey_name, survey_year, FALSE, 
#                      api_key, dd, table='B02001')
# 
# tot_pop = race[is.na(label3)]
# 
# setnames(tot_pop, 'estimate', 'total')


# Get Poverty Data --------------------------------------------------------

pov_tract0 = import_census('tract', survey_name, survey_year, FALSE, api_key, dd,
                           vars=c(pct_pov='S1701_C03_001'))

pov_tract = format_census(pov_tract0)
pov_tract$variable = NULL

pov_cnty0 = import_census('county', survey_name, survey_year, FALSE, api_key,
                          dd, vars=c(pct_pov='S1701_C03_001'))

pov_cnty = format_census(pov_cnty0)

setnames(pov_cnty, 
         c('estimate', 'moe'), 
         c('est_county', 'moe_county'),
         skip_absent = TRUE)

pov = merge(pov_tract, pov_cnty, by=c('COUNTYID', 'county'))

pov[, ":="(est = ifelse(is.na(estimate), est_county, estimate),
           error = ifelse(is.na(moe), moe_county, moe),
           missing = is.na(estimate))]

pov[, est_upper := est + error]

pov = pov[est_upper>=20]

pov = pov[,.(COUNTYID, county, GEOID, geom_name, est, est_upper, error, missing)]

pov_sf = merge(tract, pov, by='GEOID')

write_sf(pov_sf, 'data/final/poverty.geojson')

# Get fuel Source data ----------------------------------------------------

heat0 = import_census('tract', survey_name, survey_year, FALSE, 
                      api_key, dd, table='B25040')

heat1 = format_census(heat0)

heat_tot = heat1[is.na(label3), .(GEOID, estimate)]
setnames(heat_tot, 'estimate', 'total')


heat2 = heat1[!is.na(label3)]

heat2$fuel = case_when(grepl('Bottled', heat2$label3) ~ 'tank_gas',
                       grepl('Coal', heat2$label3) ~ 'coal',
                       grepl('Electricity', heat2$label3) ~ 'electricity',
                       grepl('kerosene', heat2$label3) ~ 'fuel_oil',
                       grepl('No fuel', heat2$label3) ~ 'none',
                       grepl('Solar', heat2$label3) ~ 'solar',
                       grepl('Utility', heat2$label3) ~ 'utility_gas',
                       grepl('Wood', heat2$label3) ~ 'wood',
                       .default='other')

dirty_fuels = c('coal', 'fuel_oil', 'wood')

bad_fuel = heat2[fuel %in% dirty_fuels, 
                 .(variable = 'B25040_00X',
                   fuel = 'high_pollutant', 
                   estimate=sum(estimate),
                   moe=NA), 
                 by=.(GEOID, COUNTYID, county, geom_name, concept)]

gas_fuel = heat2[grepl('_gas$', fuel), 
                 .(variable = 'B25040_00X',
                   fuel = 'gas', 
                   estimate=sum(estimate),
                   moe=NA), 
                 by=.(GEOID, COUNTYID, county, geom_name, concept)]

heat2$label3 = NULL

heat3 = rbind(heat2, bad_fuel, gas_fuel)


heat4 = merge(heat3, heat_tot, by='GEOID')

heat4[,pct:=round(estimate/total, 4)]

heat = dcast(heat4, GEOID + county + geom_name ~ fuel, 
             value.var = 'pct')

heatn = dcast(heat4, GEOID + county + geom_name ~ fuel, 
             value.var = 'estimate')

heat_sf = merge(tract, heat, by='GEOID')
heat_sf = heat_sf[which(!is.na(heat_sf$high_pollutant)), ]

heatn_sf = merge(tract, heatn, by='GEOID')

heat_hp = heat_sf[which(heat_sf$high_pollutant>0.2), ]
heatn_hp = heatn_sf[which(heatn_sf$high_pollutant>250), ]

write_sf(heat_sf, 'data/final/heating_fuel_source.geojson')

