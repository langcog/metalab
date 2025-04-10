library(dplyr)
library(purrr)
library(here)
library(metalabr)

metalabr:::get_cached_metalab_data(here("shinyapps", "site_data", "Rdata", "metalab.Rdata"))
cat("Generating dataset summaries from template...")

## build dataset Rmd files from Rmd template, filling in each value of dataset.
dataset_template <- readLines(here("build", "dataset-template.Rmd"))

if (!dir.exists(here("content", "dataset"))) {
  dir.create(here("content", "dataset"))
}

lapply(dataset_info$short_name, function(s_name) {
  current_dataset <- dataset_info %>% filter(short_name == s_name)
  to_write <- sapply(dataset_template, function(template_line) {
    template_line <- gsub("<<SHORT_NAME>>", current_dataset$short_name, template_line)
    template_line <- gsub("<<LONG_NAME>>", current_dataset$name, template_line)
    template_line <- gsub("<<SHORT_DESC>>", current_dataset$short_desc, template_line)
    template_line <- gsub("<<NUMERIC_SUMMARY>>",
                          paste(floor(current_dataset$num_papers), "papers |",
                                floor(current_dataset$num_experiments), "experiments |",
                                floor(current_dataset$num_subjects), "subjects") ,
                          template_line)
    gsub("<<DOMAIN_NAME>>", current_dataset$domain, template_line)
  })

  if (!dir.exists(here("content", "dataset", s_name))) {
    dir.create(here("content", "dataset", s_name))
  }

  cat(to_write,
      file = here("content", "dataset", s_name, "index.Rmd"),
      sep = "\n")

  file.copy(from = here("static", current_dataset$src),
            to = here("content", "dataset", s_name, "featured.png"))
})

blogdown::build_site(build_rmd = TRUE)
cat("Generated dataset documentation templates successfully, now run blogdown::serve_site()\n")
