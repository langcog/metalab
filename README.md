# Developing for Metalab

Building MetaLab locally will allow you to make changes, including
text or data updates, adding new pages, or enhancing Shiny
applications.

## Software Requirements (one-time setup)

- [R](https://cloud.r-project.org/) >= 4.02
- [Hugo Extended](https://gohugo.io/getting-started/installing/) >= v0.74.3

One easy way to install Hugo Extended is to use the blogdown
package.

```
install.packages("markdown")
install.packages("blogdown") #only required if you do not already have it
blogdown::install_hugo()
```

## Install the required packages (one-time setup)

To install all the required R packages on your system, run the
following commad after opening this project in RStudio:

```
renv::restore()
```

## Updating to latest data (optional)

If the spreadsheets containing the meta-analyses have been updated,
you must update the data in the repository. The following command will
download the datasets and commit any changes to the repository.

```
source(here::here("build", "update-metalab-data.R"))
```

If you do not run the command above, your build will use the datasets
that the currently deployed version of MetaLab uses.

## Building MetaLab (each time you want to make changes)

You are now ready to build MetaLab. The commands below will serve the
site locally on your computer. The build script may take a few minutes
to run. When completed, it will be serving a local copy of the MetaLab
site at http://localhost:4321


```
source(here::here("build", "build-metalab-site.R"))
blogdown::serve_site()
```

## Editing content

You can now try editing existing content in the `content`
directory. Your changes will automatically reload in your web browser.

## Publishing Content

Changes pushed to the `main` branch, either directly or via a pull
request, will trigger a build of MetaLab in the Actions tab. When the
build is complete, the new site will be deployed to the `gh-pages`
branch, and the Shiny applications will be uploaded to the Shiny
server.

## Running Shiny Applications locally

```
## build and run, e.g., the visualization Shiny app
## (substitute "visualization" with any shiny app directory in ./shinyapps)
options(shiny.autoreload = TRUE)
shiny::runApp(here::here("shinyapps", "visualization")) 
```
