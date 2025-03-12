# Packages

library(dplyr)
library(here)
library(stringr)
library(tidyr)
library(xml2)
library(tibble)
library(polite)
library(rvest)
library(purrr)
library(lubridate)

# Scrape Site Map and Clean

raw_xml <- xml2::read_xml("https://tim.blog/post-sitemap2.xml")

site_df <- raw_xml |> 
  xml2::xml_ns_strip() |> 
  xml2::xml_find_all(".//url") |> 
  xml2::xml_find_all(".//loc") |> 
  xml2::xml_text() |> 
  tibble::as_tibble_col(column_name = "urls") |> 
  tidyr::separate_wider_regex(
    urls,
    patterns = c(
      "https://tim.blog/",
      year = "[:digit:]{4}",
      "/",
      month = "[:digit:]{2}",
      "/",
      day = "[:digit:]{2}",
      "/",
      article = ".*",
      "/"
    ),
    cols_remove = FALSE
  ) |> 
  dplyr::mutate(
    upload_date = lubridate::ymd(paste0(year, month, day)),
    .keep = "unused"
  )

# disregard non-pertinent urls after manual review of site_df
black_list <- c("transcript", "transcipt", "in-case-you-missed",
                "recap", "tools-of-titans", "cockpunch", "top-",
                "insights-from-")


podcast_df <- site_df |> 
  # filtering to on or after the first podcast episode
  dplyr::filter(upload_date >= as.Date("2014-04-22")) |>
  # removing a stretch of time where old podcasts were combined to make a new podcast
  dplyr::filter(upload_date > as.Date("2024-08-29") |
                  upload_date < as.Date("2024-05-16")) |>
  dplyr::filter(stringr::str_detect(article, paste(black_list, collapse = "|")) == FALSE) |> 
  # removing one-off recap that would cause duplicate show links
  dplyr::filter(article != "the-30-most-popular-episodes-of-the-tim-ferriss-show-from-2022")

# Scrape Show Links

session <- polite::bow("https://tim.blog/")

get_show_links <- function(url) {
  tryCatch(
    {
      foo <- session |> 
        polite::nod(path = url) |>
        polite::scrape() |> 
        rvest::html_elements(".wp-block-list li a")
      
      bar <- data.frame(
        link_title = foo |> rvest::html_text(),
        link_url = foo |> rvest::html_attr("href")
      )
      
      return(bar)
    }, 
    
    error = function(msg) {
      message(paste("The article", url, "encountered an issue when scraping show links."))
      return(NA)
    }
  )
}

show_links_df <- podcast_df |> 
  dplyr::mutate(show_links = purrr::map(urls, get_show_links)) |> 
  tidyr::unnest_longer(show_links) |> 
  tidyr::unnest_wider(show_links)

save(show_links_df, file = here::here("data/show_links_df.rda"))
