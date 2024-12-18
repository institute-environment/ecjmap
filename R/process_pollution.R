

# Description -------------------------------------------------------------

#' This script processes data for point pollution sites from the EPA. Superfund
#' sites that are on the National Priority list for rehabilitation and 
#' Brownfield sites.
#' 
#' 
#' Superfund Sites
#' https://hub.arcgis.com/datasets/c2b7cdff579c41bbba4898400aa38815/
#' 
#' Brownsfield Sites
#' https://www.epa.gov/frs/geospatial-data-download-service
#' 
#' Mercury Pollution
#' https://drive.google.com/drive/u/0/folders/1sBv3L0vG8ZHb-ZVfc6WV9cnyo0_bsOMk


# Setup -------------------------------------------------------------------

library('httr')
library('sf')

ca = st_read('data/clean/california.geojson')


# Functions ---------------------------------------------------------------

#loads write_sf
source('R/functions.R')

read_in_water = function(fn, layer_name) {
  vars = c('wbname', 'wbtype', 'est_size_a', 'size_asses')
  
  x = st_read(fn, layer=layer_name)
  st_geometry(x) = 'geometry'
  
  names(x) = tolower(names(x))
  
  x$wbname = ifelse(trimws(x$wbname)=='', 'Unknown', x$wbname)
  
  x = st_transform(x, 4326)
  
  x = x[, vars]
  
  if (grepl("With_HG", layer_name, fixed=TRUE)) {
    x$hg_status = 'Contains mercury'
  } else {
    x$hg_status = 'No mercury detected'
  }
  
  return(x)
}

# Superfund Sites ---------------------------------------------------------
#read in data, remove periods and replace them with underscores
#superfund = read.csv('data/raw/Superfund National Priorities List (NPL) Sites with Status Information.csv')
#names(superfund) = gsub('\\.', '_', names(superfund))

#Read in data
sf_url = "https://services.arcgis.com/cJ9YHowT8TU7DUyn/arcgis/rest/services/Superfund_National_Priorities_List_(NPL)_Sites_with_Status_Information/FeatureServer"


superfund = query_arcgis(sf_url, "State = 'California'")

#variables we want to include in the output data
voi = c('Site_Name', 'Site_Score', 'Site_EPA_ID', 'SEMS_ID', 'City',
           'County', 'Status', 'Date_Proposed', 'Date_Added', 'Date_Removed', 
           'Site_Listing_Narrative', 'Site_Progress_Profile')

#convert date strings to dates
superfund$Date_Proposed = as.Date(superfund$Proposed_Date, format='%m/%d/%Y')
superfund$Date_Added = as.Date(superfund$Listing_Date, format='%m/%d/%Y')
superfund$Date_Removed = as.Date(superfund$Deletion_Date, format='%m/%d/%Y')

#only select variables on interest
superfund_final = superfund[, voi]

write_sf(superfund_final, 'data/final/superfund_sites.geojson')


# Brownfields Sites -------------------------------------------------------

# b_url = 'https://ofmpub.epa.gov/frs_public2/frs_rest_services.get_facilities?'
# 
# args = 'latitude83=38.5&longitude83=-121.5&search_radius=25&pgm_sys_acrnm=ACRES&output=JSON'
# 
# bq = paste0(b_url, args)
# 
# b_resp = GET(bq)

brownfields_url = 'https://edg.epa.gov/data/public/OEI/FRS/FRS_Interests_Download.zip'

brownfields_zip = 'data/raw/FRS_Interests_Download.zip'

brownfields_gdb = 'data/raw/FRS_INTERESTS.gdb'

#takes 15-20 minutes to download
download_if_missing(url = brownfields_url,
                    filename = brownfields_zip, 
                    filename_check = brownfields_gdb, 
                    overwrite = TRUE,
                    download_timeout=2400)

#get layer names
frs_fn = 'data/raw/FRS_INTERESTS.gdb'
frs_layers = st_layers(frs_fn)

#read in data and reproject
acres = st_read(frs_fn, layer='ACRES')
acres = st_transform(acres, 4326)

#filter to california
ca_acres = filter_to_boundary(acres, ca)

#change names
names(ca_acres) = tolower(names(ca_acres))
names(ca_acres)[32] = 'geometry'
st_geometry(ca_acres) <- 'geometry'

#variables of interest
voi = c('registry_id', 'primary_name', 'location_address', 'city_name', 'county_name',
        'postal_code', 'fips_code', 'accuracy_value', 'create_date', 
        'last_reported_date', 'geometry')

ca_acres = ca_acres[,voi]

#write data
write_sf(ca_acres, 'data/final/brownfields.geojson')


# Mercury Impacted Streams ------------------------------------------------

hg_path = 'data/raw/HGFeatures.gdb'

st_layers(hg_path)

hg_lines = rbind(read_in_water(hg_path, 'Merge_Line_With_HG'),
                 read_in_water(hg_path, 'Merge_Line_No_HG'))

hg_lines$id = 1:nrow(hg_lines)

hg_polys = rbind(read_in_water(hg_path, 'Merge_Poly_With_HG'),
                 read_in_water(hg_path, 'Merge_Poly_No_HG'))

hg_polys$id = 1:nrow(hg_polys)


write_sf(hg_lines, 'data/final/mercury_lines.geojson')
write_sf(hg_polys, 'data/final/mercury_polygons.geojson')

