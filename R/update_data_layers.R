
# Description -------------------------------------------------------------

#' This script takes all the geojson files in the data/clean/ directory,
#' converts them to .js files, adds "var VARNAME =" to the beginning of the file
#' and moves them to docs/layers

in_dir = 'data/final'
out_dir = 'docs/layers'

# Function ----------------------------------------------------------------

geojson_to_js = function(geo_fn, var_name, js_dir='docs/layers') {
  slug = gsub('\\.geojson', '', basename(geo_fn))
  
  out_dir = gsub('/$|\\$|\\\\$', '', out_dir)
  
  js_fn = paste0(js_dir, '/', slug, '.js')
  
  geo_lines = readLines(geo_fn)
  
  geo_lines[1] = paste('var', var_name, '=', geo_lines[1])
  
  writeLines(geo_lines, js_fn)
  
  return(var_name)
  
}

# script ------------------------------------------------------------------

(geojsons = list.files('data/final', pattern="geojson$", full.names = TRUE))

var_names = c('brownfields', 'fire', 'regions', 'fuel', 'hg_lines',
              'hg_polys', 'mines', 'native_boundary', 'native_lands',
              'north_state', 'poverty', 'pc_geo', 'pc_pop', 'superfund', 
              'transit', 'tribal', 'tribal_boundary')

mapply(geojson_to_js, geojsons, var_names)
