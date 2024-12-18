
# Description -------------------------------------------------------------

#' This script imports data on shortages of health care workers downloaded from
#' https://data.hrsa.gov/data/download under "Shortage Areas". It subsets the
#' data to only include shortage areas from CA and removes unnecessary 
#' variables. It also splits the data into areas where the entire geographic 
#' region is experiencing a shortage ('geo') and areas where only certain
#' populations are experiencing a shortage ('pop'). This is so they can be 
#' displayed differently on the web map.
#' 
#' Currently the script focuses on areas of primary care shortages but 
#' data is also available for dental and mental health care.

library('sf')

source('R/functions.R')

datapath = 'data/raw'


# Functions ---------------------------------------------------------------

#' Imports polygons from the HRSA website and filters them to only include
#' shortage areas for California
import_health_polygons = function(abbrev, ext, path)  {
  
  slug = paste0(abbrev, '_',  toupper(ext))
  
  ln = paste0(slug, '_DET_CUR_VX')
  fn = file.path(path, slug, paste0(ln, '.', ext))
  
  p = st_read(fn, layer=ln)
  
  if (!'MctaScore' %in% names(p)) {
    p$MctaScore = NA
  }
  
  p_ca = p[which(p$CStNM=='California'), ]
  
  return(p_ca)
  
}

# Primary Care Data -------------------------------------------------------

primary_care_url = "https://data.hrsa.gov/DataDownload/DD_Files/HPSA_PLYPC_SHP.zip"

primary_care_zip = 'data/raw/HPSA_PLYPC_SHP.zip'

primary_care_shp = 'data/raw/HPSA_PLYPC_SHP/HPSA_PLYPC_SHP_DET_CUR_VX.shp' 

#this file is quite large (115mb) and will a few minutes to download
download_if_missing(url = primary_care_url,
                    filename = primary_care_zip, 
                    filename_check = primary_care_shp, 
                    overwrite = TRUE,
                    download_timeout=800)

#variables we care about, see metatdata on teh website for explanations
pc_voi = c('HpsSrcID', 'HpsNM', 'HpsScore', 'HpsFte', 'HpsShtg', 
           'HpsFormlRt', 'HpsPpPdRtG', 'HpsDgnPp', 'HpsEsUsvPp',
           'HpsPpTypDe', 'RurStatDes', 'geometry')

#import data
pc0 = import_health_polygons('HPSA_PLYPC', 'shp', datapath)

#select only variables we care about
pc = pc0[, pc_voi]

#is the area geographic (aka everyone is experiencing a shortage) or is it only
#certain populations
pc$is_geo = grepl('Geographic', pc$HpsPpTypDe)

#what population is experiencing the PCP shortage
pc$pop_type = ifelse(grepl('Geo', pc$HpsPpTypDe), 
                     'All',
                     gsub(' Population HPSA', '', pc$HpsPpTypDe))

#percent of population that is underserved
pc$pct_underserved = round(pc$HpsEsUsvPp/pc$HpsDgnPp*100, 1)

#renaming variables because the names are difficult to read
new_names = c('id', 'name','score', 'fte', 'fte_short', 'current_ratio', 
              'target_ratio', 'tot_pop', 'underserved', 'rural')

names(pc)[c(1:9, 11)] = new_names

#final variables
final_vars = c(new_names, 'pct_underserved', 'pop_type', 'is_geo', 'geometry')

#selecting final variables
pc_final = pc[, final_vars]

#transforming to WGS84 (EPSG 4326)
pc_final = st_transform(pc_final, 4326)

#splitting data when writing so we can shade them differently
write_sf(pc_final[pc_final$is_geo, ], 'data/final/primary_care_geo.geojson')
write_sf(pc_final[!pc_final$is_geo, ], 'data/final/primary_care_pop.geojson')



