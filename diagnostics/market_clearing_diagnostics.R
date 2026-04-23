#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(ggplot2)
})

args <- commandArgs(trailingOnly = TRUE)
input_csv <- if (length(args) >= 1) args[[1]] else "outputs/diagnostics/market_log_latest.csv"
output_dir <- if (length(args) >= 2) args[[2]] else "outputs/diagnostics/market_clearing"

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

log <- read.csv(input_csv, stringsAsFactors = FALSE)

required_cols <- c(
  "tick", "population", "employed", "unemployed", "housed", "unhoused",
  "residential_units", "vacant_residential_units",
  "commercial_units", "vacant_commercial_units",
  "active_firms", "firm_job_vacancies",
  "committed_output", "realized_sales", "unsold_output",
  "mean_wage", "mean_residential_rent", "mean_commercial_rent", "mean_goods_price"
)

missing_cols <- setdiff(required_cols, names(log))
if (length(missing_cols) > 0) {
  stop("Input CSV is missing required columns: ", paste(missing_cols, collapse = ", "))
}

log$housing_excess_supply <- log$vacant_residential_units
log$housing_excess_demand <- log$unhoused
log$labor_excess_supply <- log$unemployed
log$labor_excess_demand <- log$firm_job_vacancies
log$commercial_space_excess_supply <- log$vacant_commercial_units
log$goods_excess_supply <- log$unsold_output
log$housing_vacancy_rate <- ifelse(log$residential_units > 0, log$vacant_residential_units / log$residential_units, NA_real_)
log$commercial_vacancy_rate <- ifelse(log$commercial_units > 0, log$vacant_commercial_units / log$commercial_units, NA_real_)
log$goods_unsold_rate <- ifelse(log$committed_output > 0, log$unsold_output / log$committed_output, NA_real_)
log$employment_rate <- ifelse(log$population > 0, log$employed / log$population, NA_real_)
log$housing_rate <- ifelse(log$population > 0, log$housed / log$population, NA_real_)

write.csv(log, file.path(output_dir, "market_log_enriched.csv"), row.names = FALSE)

summary_rows <- data.frame(
  metric = c(
    "final_population",
    "final_employed",
    "final_unemployed",
    "final_housed",
    "final_unhoused",
    "final_vacant_residential_units",
    "final_vacant_commercial_units",
    "final_unsold_output",
    "max_unhoused",
    "max_unemployed",
    "max_vacant_residential_units",
    "max_vacant_commercial_units",
    "max_unsold_output",
    "tick_first_zero_housed"
  ),
  value = c(
    tail(log$population, 1),
    tail(log$employed, 1),
    tail(log$unemployed, 1),
    tail(log$housed, 1),
    tail(log$unhoused, 1),
    tail(log$vacant_residential_units, 1),
    tail(log$vacant_commercial_units, 1),
    tail(log$unsold_output, 1),
    max(log$unhoused, na.rm = TRUE),
    max(log$unemployed, na.rm = TRUE),
    max(log$vacant_residential_units, na.rm = TRUE),
    max(log$vacant_commercial_units, na.rm = TRUE),
    max(log$unsold_output, na.rm = TRUE),
    ifelse(any(log$housed == 0), min(log$tick[log$housed == 0]), NA)
  )
)
write.csv(summary_rows, file.path(output_dir, "market_failure_summary.csv"), row.names = FALSE)

plot_long <- function(data, cols, title, y_label, filename) {
  long <- do.call(rbind, lapply(cols, function(col) {
    data.frame(tick = data$tick, metric = col, value = data[[col]])
  }))
  p <- ggplot(long, aes(x = tick, y = value, color = metric)) +
    geom_line(linewidth = 0.75) +
    labs(title = title, x = "Tick", y = y_label, color = NULL) +
    theme_minimal(base_size = 12)
  ggsave(file.path(output_dir, filename), p, width = 8, height = 5, dpi = 160)
}

plot_long(
  log,
  c("employed", "unemployed", "housed", "unhoused"),
  "Worker state counts",
  "Workers",
  "worker_state_counts.png"
)

plot_long(
  log,
  c("housing_excess_supply", "housing_excess_demand"),
  "Housing market non-clearing",
  "Units / workers",
  "housing_market_nonclearing.png"
)

plot_long(
  log,
  c("labor_excess_supply", "labor_excess_demand"),
  "Labor market non-clearing",
  "Workers / vacancies",
  "labor_market_nonclearing.png"
)

plot_long(
  log,
  c("commercial_space_excess_supply"),
  "Commercial-space excess supply",
  "Vacant commercial units",
  "commercial_space_excess_supply.png"
)

plot_long(
  log,
  c("committed_output", "realized_sales", "goods_excess_supply"),
  "Goods market output and unsold goods",
  "Goods",
  "goods_market_nonclearing.png"
)

plot_long(
  log,
  c("mean_wage", "mean_residential_rent", "mean_commercial_rent", "mean_goods_price"),
  "Prices over time",
  "Mean price/rent/wage",
  "prices_over_time.png"
)

plot_long(
  log,
  c("employment_rate", "housing_rate", "housing_vacancy_rate", "commercial_vacancy_rate", "goods_unsold_rate"),
  "Rates over time",
  "Rate",
  "rates_over_time.png"
)

cat("Input:", input_csv, "\n")
cat("Output directory:", output_dir, "\n")
cat("\nMarket failure summary:\n")
print(summary_rows)
