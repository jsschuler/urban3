#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(ggplot2)
})

args <- commandArgs(trailingOnly = TRUE)
input_csv <- if (length(args) >= 1) args[[1]] else "outputs/diagnostics/lots_latest.csv"
output_dir <- if (length(args) >= 2) args[[2]] else "outputs/diagnostics/rent_gradient"

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

lots <- read.csv(input_csv, stringsAsFactors = FALSE)

required_cols <- c(
  "tick", "lot_id", "x", "y",
  "residential_units", "commercial_units",
  "occupied_residential", "occupied_commercial",
  "vacant_residential", "vacant_commercial",
  "residential_rent", "commercial_rent"
)

missing_cols <- setdiff(required_cols, names(lots))
if (length(missing_cols) > 0) {
  stop("Input CSV is missing required columns: ", paste(missing_cols, collapse = ", "))
}

weighted_centroid <- function(x, y, w) {
  total <- sum(w, na.rm = TRUE)
  if (total <= 0) {
    return(c(mean(range(x)), mean(range(y))))
  }
  c(sum(x * w, na.rm = TRUE) / total, sum(y * w, na.rm = TRUE) / total)
}

safe_cor <- function(x, y) {
  if (sd(x, na.rm = TRUE) == 0 || sd(y, na.rm = TRUE) == 0) return(NA_real_)
  cor(x, y, use = "complete.obs")
}

geom_center <- c(mean(range(lots$x)), mean(range(lots$y)))
res_centroid <- weighted_centroid(lots$x, lots$y, lots$occupied_residential)
com_centroid <- weighted_centroid(lots$x, lots$y, lots$occupied_commercial)

lots$dist_geometric_center <- abs(lots$x - geom_center[[1]]) + abs(lots$y - geom_center[[2]])
lots$dist_res_occupancy_centroid <- abs(lots$x - res_centroid[[1]]) + abs(lots$y - res_centroid[[2]])
lots$dist_com_occupancy_centroid <- abs(lots$x - com_centroid[[1]]) + abs(lots$y - com_centroid[[2]])
lots$total_units <- lots$residential_units + lots$commercial_units
lots$total_occupied <- lots$occupied_residential + lots$occupied_commercial
lots$commercial_vacancy_rate <- ifelse(lots$commercial_units > 0, lots$vacant_commercial / lots$commercial_units, NA_real_)
lots$residential_vacancy_rate <- ifelse(lots$residential_units > 0, lots$vacant_residential / lots$residential_units, NA_real_)

rent_correlations <- data.frame(
  rent = c(
    "residential_rent",
    "commercial_rent",
    "residential_rent",
    "commercial_rent",
    "residential_rent",
    "commercial_rent"
  ),
  distance = c(
    "geometric_center",
    "geometric_center",
    "residential_occupancy_centroid",
    "residential_occupancy_centroid",
    "commercial_occupancy_centroid",
    "commercial_occupancy_centroid"
  ),
  correlation = c(
    safe_cor(lots$dist_geometric_center, lots$residential_rent),
    safe_cor(lots$dist_geometric_center, lots$commercial_rent),
    safe_cor(lots$dist_res_occupancy_centroid, lots$residential_rent),
    safe_cor(lots$dist_res_occupancy_centroid, lots$commercial_rent),
    safe_cor(lots$dist_com_occupancy_centroid, lots$residential_rent),
    safe_cor(lots$dist_com_occupancy_centroid, lots$commercial_rent)
  )
)

write.csv(rent_correlations, file.path(output_dir, "rent_distance_correlations.csv"), row.names = FALSE)

bin_width <- 5
lots$distance_bin <- floor(lots$dist_geometric_center / bin_width) * bin_width

binned <- aggregate(
  cbind(
    residential_rent,
    commercial_rent,
    occupied_residential,
    occupied_commercial,
    residential_vacancy_rate,
    commercial_vacancy_rate
  ) ~ distance_bin,
  data = lots,
  FUN = mean,
  na.rm = TRUE
)
binned$n_lots <- as.integer(table(lots$distance_bin)[as.character(binned$distance_bin)])
write.csv(binned, file.path(output_dir, "rent_distance_bins.csv"), row.names = FALSE)

centers <- data.frame(
  center = c("geometric", "residential occupancy", "commercial occupancy"),
  x = c(geom_center[[1]], res_centroid[[1]], com_centroid[[1]]),
  y = c(geom_center[[2]], res_centroid[[2]], com_centroid[[2]])
)
write.csv(centers, file.path(output_dir, "centers.csv"), row.names = FALSE)

plot_scatter <- function(data, distance_col, rent_col, title, filename) {
  p <- ggplot(data, aes(x = .data[[distance_col]], y = .data[[rent_col]])) +
    geom_point(alpha = 0.35, size = 1.2, color = "#496f9f") +
    geom_smooth(method = "loess", se = TRUE, color = "#bf4f45", linewidth = 0.8) +
    labs(
      title = title,
      x = "Taxicab distance",
      y = gsub("_", " ", rent_col)
    ) +
    theme_minimal(base_size = 12)
  ggsave(file.path(output_dir, filename), p, width = 7, height = 5, dpi = 160)
}

plot_scatter(
  lots,
  "dist_geometric_center",
  "residential_rent",
  "Residential rent vs distance from geometric center",
  "residential_rent_vs_geometric_center.png"
)

plot_scatter(
  lots,
  "dist_geometric_center",
  "commercial_rent",
  "Commercial rent vs distance from geometric center",
  "commercial_rent_vs_geometric_center.png"
)

plot_scatter(
  lots,
  "dist_res_occupancy_centroid",
  "residential_rent",
  "Residential rent vs distance from residential occupancy centroid",
  "residential_rent_vs_residential_centroid.png"
)

plot_scatter(
  lots,
  "dist_com_occupancy_centroid",
  "commercial_rent",
  "Commercial rent vs distance from commercial occupancy centroid",
  "commercial_rent_vs_commercial_centroid.png"
)

long_binned <- rbind(
  data.frame(distance_bin = binned$distance_bin, rent = binned$residential_rent, type = "residential"),
  data.frame(distance_bin = binned$distance_bin, rent = binned$commercial_rent, type = "commercial")
)

p_bins <- ggplot(long_binned, aes(x = distance_bin, y = rent, color = type)) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2) +
  scale_color_manual(values = c(residential = "#3d8b6d", commercial = "#b5654d")) +
  labs(
    title = "Mean rent by distance bin from geometric center",
    x = paste0("Distance bin, width ", bin_width),
    y = "Mean rent",
    color = "Use"
  ) +
  theme_minimal(base_size = 12)
ggsave(file.path(output_dir, "mean_rent_by_distance_bin.png"), p_bins, width = 7, height = 5, dpi = 160)

plot_map <- function(data, fill_col, title, filename, log_scale = FALSE) {
  p <- ggplot(data, aes(x = x, y = y, fill = .data[[fill_col]])) +
    geom_tile() +
    coord_equal() +
    labs(title = title, x = "x", y = "y", fill = gsub("_", " ", fill_col)) +
    theme_minimal(base_size = 12)
  if (log_scale) {
    p <- p + scale_fill_viridis_c(trans = "log10", option = "magma", na.value = "grey20")
  } else {
    p <- p + scale_fill_viridis_c(option = "magma", na.value = "grey20")
  }
  ggsave(file.path(output_dir, filename), p, width = 6, height = 5.5, dpi = 160)
}

plot_map(lots, "residential_rent", "Residential rent map", "residential_rent_map.png")
plot_map(lots, "commercial_rent", "Commercial rent map, log scale", "commercial_rent_map_log.png", log_scale = TRUE)
plot_map(lots, "occupied_residential", "Residential occupancy map", "residential_occupancy_map.png")
plot_map(lots, "occupied_commercial", "Commercial occupancy map", "commercial_occupancy_map.png")

high_rent_vacant <- lots[order(lots$commercial_rent, decreasing = TRUE), ]
high_rent_vacant <- high_rent_vacant[high_rent_vacant$vacant_commercial > 0, ]
write.csv(head(high_rent_vacant, 25), file.path(output_dir, "high_rent_vacant_commercial_lots.csv"), row.names = FALSE)

cat("Input:", input_csv, "\n")
cat("Output directory:", output_dir, "\n")
cat("Geometric center:", paste(round(geom_center, 3), collapse = ", "), "\n")
cat("Residential occupancy centroid:", paste(round(res_centroid, 3), collapse = ", "), "\n")
cat("Commercial occupancy centroid:", paste(round(com_centroid, 3), collapse = ", "), "\n")
cat("\nRent-distance correlations:\n")
print(rent_correlations)
