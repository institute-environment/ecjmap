
# Description -------------------------------------------------------------

#' This script loads the table the data dictionary for a given census survey,
#' reformats it to be more usable, and saves it for later. You can find the
#' code through the webpage for the api you are working with, all of which are
#' linked at https://www.census.gov/data/developers/data-sets.html
#' 

survey_year = 2022
survey = 'acs/acs5'

# Setup -------------------------------------------------------------------

library('jsonlite')
library('data.table')
library('stringr')

source('R/functions.R')

# functions ---------------------------------------------------------------

# Split very long label strings into multiple columns to make them easier to 
# read.
#
# label_vec     character vector, vector of all the labels from the data 
#               dictionary downloaded from the census website
#
# split_pattern character, regex string on which to split the labels. At the 
#               time of writing this code, the label categories are separated
#               by regex string '\\!\\!' (aka !!), but I don't put it past the 
#               Census to change it at some point.
# 
# Returns a data.table with rows = length(label_vec) and the number of columns
# equal to the maximum number of sections in any string, where the number of
# sections is the number separators (!!) in a label + 1. Columns are labeled as
# 'labeli' where i goes from 1 to the max section count. Values of the later
# columns are NA if a particular label doesn't have the max number of
# sections.
split_label = function(label_vec, split_pattern = '\\!\\!') {
  
  #number of sections in each string
  sections = str_count(label_vec, split_pattern) + 1 
  
  #all possible section indexes
  section_ids = 1:max(sections)
  
  # extract the value of section k for each label, where k goes from 1 to max
  # number of sections
  split_matrix = sapply(section_ids, function(k) {
    str_split_i(label_vec, split_pattern, k)
  }) 
  
  #remove extraneous punctuation and white space
  split_matrix =  gsub(':$|\\.$', '', split_matrix) |> trimws()
  
  #convert to data.table
  split_df = data.table(split_matrix)
  
  #add column names
  setnames(split_df, names(split_df), paste0('label', section_ids))
  
  return(split_df)
  
}

# read in -----------------------------------------------------------------

#extract name from survey path
survey_name = strsplit(survey, '\\/')[[1]][2]


#create path to json file for detailed tables variable list
det_json_path = paste0('https://api.census.gov/data/', survey_year, '/', survey, 
                      '/variables.json')

#create path to json file for subject tables variable list
sub_json_path = paste0('https://api.census.gov/data/', survey_year, '/', survey, 
                       '/subject/variables.json')

#Download metadata, takes about 20 seconds for 5 year ACS Detailed tables
system.time(det_vars_list <- fromJSON(det_json_path)[[1]])

#Download metadata, takes about 15 seconds for 5 year ACS subject tables
system.time(sub_vars_list <- fromJSON(sub_json_path)[[1]])

vars_list = c(det_vars_list, sub_vars_list)

#extract names of each element of list, aka the variable names
var_names = names(vars_list)

table_type = c(rep('detailed', length(det_vars_list)), 
               rep('subject', length(sub_vars_list)))

#convert list of lists to long data.table
vars_long = lapply(1:length(vars_list), function(i) {
  data.table(variable = var_names[i],
             field = names(vars_list[[i]]), 
             value = unlist(vars_list[[i]], use.names=FALSE),
             type = table_type[i]
             )
}) |> rbindlist()

#fields we don't really care about
rare_fields = c('hasGeoCollectionSupport', 'predicateOnly', 'required')

#remove fields we don't care about
vars_long = vars_long[!field %in% rare_fields] 

#go from long to wide (one row per variable)
vars = dcast(vars_long, variable + type ~ field, value.var='value')

vars[, variable := gsub('E$', '', variable)]

fn_raw = create_dd_fn('data/clean/census', survey_name, survey_year, 
                      is_split=FALSE)

write.csv(vars, fn_raw, row.names = FALSE)


labels_df = split_label(vars$label)

vars_split = cbind(vars, labels_df)

vars_split$label = NULL

#create file name
fn_split = create_dd_fn('data/clean/census', survey_name, survey_year, 
                        is_split=TRUE)

#write file
write.csv(vars_split, fn_split, row.names = FALSE)
