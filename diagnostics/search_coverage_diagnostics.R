#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(ggplot2)
})

args <- commandArgs(trailingOnly = TRUE)
input_csv <- if (length(args) >= 1) args[[1]] else "outputs/diagnostics/search_coverage_latest.csv"
output_dir <- if (length(args) >= 2) args[[2]] else "outputs/diagnostics/search_coverage"

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

coverage <- read.csv(input_csv, stringsAsFactors = FALSE)

required_cols <- c(
  "domain", "events", "lots_covered", "lot_coverage_share", "raw_draws",
  "unique_draws", "mean_raw_draws_per_event", "mean_unique_lots_per_event"
)
missing_cols <- setdiff(required_cols, names(coverage))
if (length(missing_cols) > 0) {
  stop("Input CSV is missing required columns: ", paste(missing_cols, collapse = ", "))
}

write.csv(coverage, file.path(output_dir, "search_coverage_summary.csv"), row.names = FALSE)

p_coverage <- ggplot(coverage, aes(x = reorder(domain, lot_coverage_share), y = lot_coverage_share)) +
  geom_col(fill = "#547a9b") +
  coord_flip() +
  scale_y_continuous(labels = function(x) paste0(round(100 * x), "%"), limits = c(0, 1)) +
  labs(title = "Search lot coverage by domain", x = "Domain", y = "Share of lots ever sampled") +
  theme_minimal(base_size = 12)
ggsave(file.path(output_dir, "lot_coverage_share_by_domain.png"), p_coverage, width = 7, height = 4.5, dpi = 160)

p_unique <- ggplot(coverage, aes(x = reorder(domain, mean_unique_lots_per_event), y = mean_unique_lots_per_event)) +
  geom_col(fill = "#7f9b54") +
  coord_flip() +
  labs(title = "Mean unique lots sampled per search event", x = "Domain", y = "Unique lots per event") +
  theme_minimal(base_size = 12)
ggsave(file.path(output_dir, "mean_unique_lots_per_event_by_domain.png"), p_unique, width = 7, height = 4.5, dpi = 160)

p_events <- ggplot(coverage, aes(x = reorder(domain, events), y = events)) +
  geom_col(fill = "#9b6654") +
  coord_flip() +
  labs(title = "Search event counts by domain", x = "Domain", y = "Events") +
  theme_minimal(base_size = 12)
ggsave(file.path(output_dir, "search_events_by_domain.png"), p_events, width = 7, height = 4.5, dpi = 160)

cat("Input:", input_csv, "\n")
cat("Output directory:", output_dir, "\n")
cat("\nSearch coverage summary:\n")
print(coverage)
