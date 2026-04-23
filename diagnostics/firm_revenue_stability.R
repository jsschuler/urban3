#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(ggplot2)
})

args <- commandArgs(trailingOnly = TRUE)
input_csv <- if (length(args) >= 1) args[[1]] else "outputs/diagnostics/firm_revenue_latest.csv"
output_dir <- if (length(args) >= 2) args[[2]] else "outputs/diagnostics/firm_revenue_stability"

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

panel <- read.csv(input_csv, stringsAsFactors = FALSE)

required_cols <- c(
  "tick", "firm_id", "firm_type", "active", "workers", "capital_units",
  "process_count", "commercial_units", "goods_price", "committed_output",
  "realized_sales", "unsold_output", "sold_out", "revenue",
  "wage_bill", "rent_bill", "profit"
)

missing_cols <- setdiff(required_cols, names(panel))
if (length(missing_cols) > 0) {
  stop("Input CSV is missing required columns: ", paste(missing_cols, collapse = ", "))
}

safe_cv <- function(x) {
  m <- mean(x, na.rm = TRUE)
  if (is.na(m) || m == 0) return(NA_real_)
  sd(x, na.rm = TRUE) / m
}

safe_cor_lag1 <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) < 3 || sd(x) == 0) return(NA_real_)
  cor(head(x, -1), tail(x, -1))
}

gini <- function(x) {
  x <- sort(x[is.finite(x) & x >= 0])
  n <- length(x)
  if (n == 0 || sum(x) == 0) return(NA_real_)
  sum((2 * seq_len(n) - n - 1) * x) / (n * sum(x))
}

aggregate_by_tick <- do.call(rbind, lapply(split(panel, panel$tick), function(d) {
  data.frame(
    tick = d$tick[[1]],
    active_firms = nrow(d),
    total_revenue = sum(d$revenue, na.rm = TRUE),
    mean_revenue = mean(d$revenue, na.rm = TRUE),
    median_revenue = median(d$revenue, na.rm = TRUE),
    sd_revenue = sd(d$revenue, na.rm = TRUE),
    cv_revenue = safe_cv(d$revenue),
    zero_revenue_share = mean(d$revenue == 0, na.rm = TRUE),
    sold_out_share = mean(d$sold_out, na.rm = TRUE),
    total_unsold_output = sum(d$unsold_output, na.rm = TRUE),
    total_profit = sum(d$profit, na.rm = TRUE),
    loss_firm_share = mean(d$profit < 0, na.rm = TRUE),
    revenue_gini = gini(d$revenue)
  )
}))

aggregate_by_firm <- do.call(rbind, lapply(split(panel, panel$firm_id), function(d) {
  data.frame(
    firm_id = d$firm_id[[1]],
    firm_type = d$firm_type[[1]],
    n_ticks_observed = nrow(d),
    first_tick = min(d$tick),
    last_tick = max(d$tick),
    mean_revenue = mean(d$revenue, na.rm = TRUE),
    median_revenue = median(d$revenue, na.rm = TRUE),
    sd_revenue = sd(d$revenue, na.rm = TRUE),
    cv_revenue = safe_cv(d$revenue),
    zero_revenue_share = mean(d$revenue == 0, na.rm = TRUE),
    sold_out_share = mean(d$sold_out, na.rm = TRUE),
    lag1_revenue_corr = safe_cor_lag1(d$revenue),
    mean_profit = mean(d$profit, na.rm = TRUE),
    loss_share = mean(d$profit < 0, na.rm = TRUE),
    mean_workers = mean(d$workers, na.rm = TRUE)
  )
}))

write.csv(aggregate_by_tick, file.path(output_dir, "revenue_by_tick.csv"), row.names = FALSE)
write.csv(aggregate_by_firm, file.path(output_dir, "revenue_by_firm.csv"), row.names = FALSE)

summary_rows <- data.frame(
  metric = c(
    "ticks",
    "firm_rows",
    "unique_firms",
    "final_active_firms",
    "final_total_revenue",
    "final_mean_revenue",
    "final_cv_revenue",
    "final_zero_revenue_share",
    "final_sold_out_share",
    "mean_total_revenue",
    "cv_total_revenue_over_time",
    "median_firm_cv_revenue",
    "median_firm_zero_revenue_share",
    "median_firm_lag1_revenue_corr",
    "mean_revenue_gini",
    "share_firms_lifetime_1_tick",
    "share_firms_lifetime_le_5_ticks",
    "share_firms_lifetime_ge_100_ticks",
    "continuing_firms_ge_100_ticks",
    "continuing_firm_median_cv_revenue",
    "continuing_firm_median_zero_revenue_share"
  ),
  value = c(
    length(unique(panel$tick)),
    nrow(panel),
    length(unique(panel$firm_id)),
    tail(aggregate_by_tick$active_firms, 1),
    tail(aggregate_by_tick$total_revenue, 1),
    tail(aggregate_by_tick$mean_revenue, 1),
    tail(aggregate_by_tick$cv_revenue, 1),
    tail(aggregate_by_tick$zero_revenue_share, 1),
    tail(aggregate_by_tick$sold_out_share, 1),
    mean(aggregate_by_tick$total_revenue, na.rm = TRUE),
    safe_cv(aggregate_by_tick$total_revenue),
    median(aggregate_by_firm$cv_revenue, na.rm = TRUE),
    median(aggregate_by_firm$zero_revenue_share, na.rm = TRUE),
    median(aggregate_by_firm$lag1_revenue_corr, na.rm = TRUE),
    mean(aggregate_by_tick$revenue_gini, na.rm = TRUE),
    mean(aggregate_by_firm$n_ticks_observed == 1, na.rm = TRUE),
    mean(aggregate_by_firm$n_ticks_observed <= 5, na.rm = TRUE),
    mean(aggregate_by_firm$n_ticks_observed >= 100, na.rm = TRUE),
    sum(aggregate_by_firm$n_ticks_observed >= 100, na.rm = TRUE),
    median(aggregate_by_firm$cv_revenue[aggregate_by_firm$n_ticks_observed >= 100], na.rm = TRUE),
    median(aggregate_by_firm$zero_revenue_share[aggregate_by_firm$n_ticks_observed >= 100], na.rm = TRUE)
  )
)

write.csv(summary_rows, file.path(output_dir, "revenue_stability_summary.csv"), row.names = FALSE)

plot_line <- function(data, y_col, title, y_label, filename) {
  p <- ggplot(data, aes(x = tick, y = .data[[y_col]])) +
    geom_line(color = "#3f6f8f", linewidth = 0.75) +
    labs(title = title, x = "Tick", y = y_label) +
    theme_minimal(base_size = 12)
  ggsave(file.path(output_dir, filename), p, width = 8, height = 5, dpi = 160)
}

plot_line(aggregate_by_tick, "total_revenue", "Total firm revenue over time", "Total revenue", "total_revenue_over_time.png")
plot_line(aggregate_by_tick, "cv_revenue", "Cross-firm revenue coefficient of variation", "CV", "cross_firm_revenue_cv.png")
plot_line(aggregate_by_tick, "zero_revenue_share", "Share of firms with zero revenue", "Share", "zero_revenue_share.png")
plot_line(aggregate_by_tick, "sold_out_share", "Share of firms sold out", "Share", "sold_out_share.png")
plot_line(aggregate_by_tick, "revenue_gini", "Revenue concentration across firms", "Gini", "revenue_gini.png")
plot_line(aggregate_by_tick, "loss_firm_share", "Share of firms losing money", "Share", "loss_firm_share.png")

p_hist_cv <- ggplot(aggregate_by_firm, aes(x = cv_revenue)) +
  geom_histogram(bins = 40, fill = "#6b9e77", color = "white") +
  labs(title = "Firm-level revenue CV distribution", x = "Firm revenue CV", y = "Firms") +
  theme_minimal(base_size = 12)
ggsave(file.path(output_dir, "firm_revenue_cv_distribution.png"), p_hist_cv, width = 7, height = 5, dpi = 160)

p_hist_zero <- ggplot(aggregate_by_firm, aes(x = zero_revenue_share)) +
  geom_histogram(bins = 40, fill = "#b76f51", color = "white") +
  labs(title = "Firm-level zero-revenue share distribution", x = "Zero-revenue share", y = "Firms") +
  theme_minimal(base_size = 12)
ggsave(file.path(output_dir, "firm_zero_revenue_share_distribution.png"), p_hist_zero, width = 7, height = 5, dpi = 160)

p_lifetime <- ggplot(aggregate_by_firm, aes(x = n_ticks_observed)) +
  geom_histogram(bins = 50, fill = "#7667a8", color = "white") +
  scale_x_log10() +
  labs(title = "Firm observed lifetime distribution", x = "Ticks observed, log scale", y = "Firms") +
  theme_minimal(base_size = 12)
ggsave(file.path(output_dir, "firm_lifetime_distribution.png"), p_lifetime, width = 7, height = 5, dpi = 160)

continuing <- aggregate_by_firm[aggregate_by_firm$n_ticks_observed >= 100, ]
if (nrow(continuing) > 0) {
  p_continuing_cv <- ggplot(continuing, aes(x = cv_revenue)) +
    geom_histogram(bins = 30, fill = "#5b8a91", color = "white") +
    labs(title = "Continuing-firm revenue CV distribution", x = "Revenue CV, firms observed >= 100 ticks", y = "Firms") +
    theme_minimal(base_size = 12)
  ggsave(file.path(output_dir, "continuing_firm_revenue_cv_distribution.png"), p_continuing_cv, width = 7, height = 5, dpi = 160)
}

p_revenue_profit <- ggplot(panel, aes(x = revenue, y = profit)) +
  geom_point(alpha = 0.15, size = 0.7, color = "#415b76") +
  geom_hline(yintercept = 0, linetype = "dashed", color = "#a34d4d") +
  labs(title = "Firm revenue and profit observations", x = "Revenue", y = "Profit") +
  theme_minimal(base_size = 12)
ggsave(file.path(output_dir, "revenue_profit_scatter.png"), p_revenue_profit, width = 7, height = 5, dpi = 160)

cat("Input:", input_csv, "\n")
cat("Output directory:", output_dir, "\n")
cat("\nRevenue stability summary:\n")
print(summary_rows)
