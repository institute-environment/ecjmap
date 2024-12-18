
# Description -------------------------------------------------------------

#' This script reads in a transit routes data file from the CA State GeoPortal
#' (https://gis.data.ca.gov/datasets/dd7cb74665a14859a59b8c31d3bc5a3e_0/) and
#' subsets it for only the transit routes that overlap with California. It also
#' adds a route type name variable that converts the route type ID to the name
#' of the route type (ex. light rail, train, bus etc.)


# Setup -------------------------------------------------------------------


library('sf')

#load write_sf
source('R/functions.R')


# Read in Data ------------------------------------------------------------

#read in downloaded transit routes 
trans0 = st_read('data/raw/CA_Transit_Routes.geojson')
trans0 = st_transform(trans0, 3310)

#load polygon of california for filtering to california
ca = st_read('data/clean/california.geojson')
ca = st_transform(ca, 3310)

# Route Type Conversion ---------------------------------------------------

#creating data.frame to convert 
rt_names = c('light rail', 'commuter rail', 'train', 'bus', 'boat', 'trolley')

trans_types = data.frame(route_type = 0:5,
                         route_type_name = rt_names)


# converting route type to an integer
trans0$route_type = as.integer(trans0$route_type)

#adding route_type_name to transit data
trans1 = merge(trans0, trans_types, by='route_type')


# Get Only California Transit Routes --------------------------------------

#figuring out which routes overlap with california
in_ca = st_intersects(trans1, ca, sparse = FALSE)[,1]

#subset all transit routes to only include the ones in CA
trans_ca = trans1[in_ca, ]



# Convert to Lat/Lon and Save ---------------------------------------------

trans_ll = st_transform(trans_ca, 4326) 

write_sf(trans_ll, 'data/final/transit.geojson')
