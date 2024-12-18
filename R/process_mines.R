
#' download California data
#mrds site: https://mrdata.usgs.gov/mrds/geo-inventory.php
#' download link: https://mrdata.usgs.gov/catalog/science.php?thcode=1&term=fUS06

library('httr')
library('sf')
library('data.table')
library('stringr')
library('tidyr')
library('dplyr')

source('R/functions.R')



# Functions ---------------------------------------------------------------

string_to_vec = function(string, unique_vals =TRUE, split_on=', ') {
  string_vec = strsplit(string, split_on) |> 
    unlist(use.names = FALSE) 
  
  if (unique_vals) {
    string_vec = unique(string_vec)
  }
  
  return(string_vec)
}

collapse_commodity_type = function(ctype) {
  
  if (('B' %in% ctype) | ('M' %in% ctype & 'N' %in% ctype)) {
    final_type = 'B'
  } else if ('M' %in% ctype) {
    final_type = 'M'
  } else {
    final_type = 'N'
  }
  
  return(final_type)
}


assign_commodity_type = function(prods, ctypes) {
  prod_vec = string_to_vec(prods)
  
  prod_ctypes = ctypes[commodity %in% prod_vec, com_type]
  
  mine_type = collapse_commodity_type(prod_ctypes)
  
  return(mine_type)
  
}

collapse_work_type = function(wt) {
  
  if (any(grepl('Undeground', wt)) & any(grepl('Surface', wt))) {
    final_wt = 'Surface, Underground'
    
  } else if (any(grepl('Surface', wt))) {
    final_wt = 'Surface'
  } else if (any(grepl('Underground', wt))) {
    final_wt = 'Underground'
  } else {
    final_wt = 'Unknown'
  }
  
  return(final_wt)
  
}

collapse_products = function(prods) {
  
  prods = prods[!is.na(prods)]
  
  prods_string = paste0(prods, collapse = ', ')
  
  prod_list = string_to_vec(prods_string)
  
  prod_string_unique = paste0(prod_list, collapse = ', ')
  
  return(prod_string_unique)
}

collapse_status = function(status) {
  if (any(grepl('Producer', status))) {
    
    if (any(status=='Producer')) {
      mine_status = 'In production'
    } else {
      mine_status = 'Not in production'
    }
    
  } else {
    mine_status = 'Unknown'
  }
  
   return(mine_status)
}


pick_toxic_product = function(prods, toxics) {
  
  prod_vec = string_to_vec(prods, unique_vals=FALSE)
  
  if (length(intersect(prod_vec, toxics))==0) {
    
    prod_tab = table(prod_vec)
    final_product = names(prod_tab[which.max(prod_tab)])
    
  } else {
    
    for (mine_product in toxics) {
      if (mine_product %in% prod_vec) {
        final_product = mine_product
        break
      }
    }
  }
  
  return(final_product)
}

pick_top_product = function(prods, ctype, toxics, stones) {
  top_prod = pick_toxic_product(prods, toxics)
  
  if (! top_prod %in% toxics) {
    if (multi_grepl(stones, top_prod)) {
      top_prod = 'Clay or Stone'
    } else if (ctype == 'M') {
      top_prod = 'Other Metal'
    } else if (ctype == 'N') {
      top_prod = 'Other Non-metal'
    } else {
      top_prod = 'Mixed'
      
    }
  }
  
  return(top_prod)
  
}

create_link = function(URL, name) {
  
  href = paste0("<a href=\"", URL, "\" target=\"_blank\">", name, "</a>")
  
  return(href)
}

# Read In Data ------------------------------------------------------------

mrds_url = 'https://mrdata.usgs.gov/mrds/output/mrds-fUS06.zip'

mrds_zip = 'data/raw/mrds-fUS06.zip'

mrds_shp = gsub('\\.zip$', '/mrds-fUS06.shp', mrds_zip)

download_if_missing(url = mrds_url, 
                    filename = mrds_zip, 
                    filename_check = mrds_shp,
                    overwrite = FALSE)

mrds_sf = st_read(mrds_shp)

mrds = st_drop_geometry(mrds_sf) 
setDT(mrds)


# Filter to high quality data ---------------------------------------------


voi = c('dep_id', 'mrds_id', 'mas_id', 'site_name', 'latitude', 'longitude',
        'commod1', 'work_type', 'names', 'score', 'dev_stat', 'url',
        'commod2', 'commod3')


mines = mrds[grepl('Producer', dev_stat) & score %in% c('A','B','C') 
                & !is.na(commod1), 
             ..voi]

#filling in IDs
mines[, ":="(mrds_id = ifelse(is.na(mrds_id), dep_id, mrds_id),
             mas_id = ifelse(is.na(mas_id), dep_id, mas_id))]

# Clean commodity data ----------------------------------------------------


sub_categories = c(', Construction', ', Crushed/Broken', ', Dimension',
                   ', General')

mines[, ":="(products = multi_gsub(sub_categories, '', commod1),
             products2 = multi_gsub(sub_categories, '', commod2),
             proucts3 = multi_gsub(sub_categories, '', commod3))]

all_prods = string_to_vec(c(mines$products, mines$products2, mines$proucts3))

#fwrite(data.table(commodity = all_prods), 'data/raw/all_mine_commodities.csv')
prod_types = fread('data/clean/all_mine_commodity_types.csv')

mines[, all_products := collapse_products(c(products, products2)), by=dep_id]

mines[, com_type := sapply(all_products, assign_commodity_type, ctypes=prod_types)]

# Collapsing mine observations by mrds_id ---------------------------------

toxic_materials = c('Uranium', 'Lead', 'Mercury', 'Chromium', 'Silver', 'Gold',
                    'Copper', 'Asbestos')

clay_stone = c('Clay', 'Granite', '(S|s)tone', 'Marble', 'Pumice', 'Sand', 
               'Kaolin')

#selecting observations with a higher score
mines = mines[, .SD[score==min(score)], by=mrds_id]
mines = mines[, .SD[score==min(score)], by=mas_id]

mines[, ":=" (
    top_product = pick_top_product(products, com_type, toxic_materials, clay_stone),
    work_type = collapse_work_type(work_type),
    link = create_link(url, site_name)
  ),
  by=dep_id]



# Make spatial ------------------------------------------------------------

final_vars = c('dep_id', 'mrds_id', 'site_name', 'latitude', 'longitude',
               'work_type', 'dev_stat', 'all_products', 'top_product',
               'score', 'link')

mines_final = mines[dev_stat=='Past Producer', ..final_vars]
mines_sf = st_as_sf(x=mines_final,
                    coords=c('longitude', 'latitude'),
                    crs=st_crs(mrds_sf))


# Save Data ----------------------------------------------------------------

write_sf(mines_sf, 'data/final/mines.geojson')


