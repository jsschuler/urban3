#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(args) >= 1) args[[1]] else "outputs/overnight"
plot_dir <- file.path(out_dir, "plots")
dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)

market <- read.csv(file.path(out_dir, "market_log.csv"))
delta <- read.csv(file.path(out_dir, "market_log_deltas.csv"))
events <- read.csv(file.path(out_dir, "tick_events.csv"))
fail <- read.csv(file.path(out_dir, "firm_failures.csv"))

# Reconstruct selected state variables from additive deltas
recon <- data.frame(
  tick = delta$tick,
  population = cumsum(delta$d_population),
  employed = cumsum(delta$d_employed),
  active_firms = cumsum(delta$d_active_firms),
  realized_sales = cumsum(delta$d_realized_sales),
  mean_commercial_rent = cumsum(delta$d_mean_commercial_rent)
)

# Consistency check against direct market log
chk <- merge(
  recon,
  market[, c("tick", "population", "employed", "active_firms", "realized_sales", "mean_commercial_rent")],
  by = "tick",
  suffixes = c("_recon", "_log")
)
check_tbl <- data.frame(
  variable = c("population", "employed", "active_firms", "realized_sales", "mean_commercial_rent"),
  max_abs_error = c(
    max(abs(chk$population_recon - chk$population_log)),
    max(abs(chk$employed_recon - chk$employed_log)),
    max(abs(chk$active_firms_recon - chk$active_firms_log)),
    max(abs(chk$realized_sales_recon - chk$realized_sales_log)),
    max(abs(chk$mean_commercial_rent_recon - chk$mean_commercial_rent_log))
  )
)
write.csv(check_tbl, file.path(plot_dir, "reconstruction_check.csv"), row.names = FALSE)

png(file.path(plot_dir, "state_timeseries.png"), width = 1400, height = 900)
par(mfrow = c(2, 2), mar = c(4, 4, 2, 1))
plot(market$tick, market$population, type = "l", lwd = 2, col = "steelblue",
     xlab = "Tick", ylab = "Population", main = "Population")
plot(market$tick, ifelse(market$population > 0, market$employed / market$population, NA),
     type = "l", lwd = 2, col = "darkgreen", xlab = "Tick", ylab = "Employment Rate", main = "Employment Rate")
plot(market$tick, market$active_firms, type = "l", lwd = 2, col = "firebrick",
     xlab = "Tick", ylab = "Active Firms", main = "Firm Count")
plot(market$tick, market$mean_commercial_rent, type = "l", lwd = 2, col = "purple4",
     xlab = "Tick", ylab = "Mean Commercial Rent", main = "Commercial Rent")
dev.off()

png(file.path(plot_dir, "event_flows.png"), width = 1400, height = 900)
par(mfrow = c(2, 2), mar = c(4, 4, 2, 1))
plot(events$tick, events$firm_entries, type = "l", lwd = 2, col = "darkgreen",
     xlab = "Tick", ylab = "Count", main = "Firm Entries per Tick")
plot(events$tick, events$firm_exits, type = "l", lwd = 2, col = "firebrick",
     xlab = "Tick", ylab = "Count", main = "Firm Exits per Tick")
plot(events$tick, events$hires, type = "l", lwd = 2, col = "dodgerblue4",
     xlab = "Tick", ylab = "Count", main = "Hires per Tick")
plot(events$tick, events$layoffs, type = "l", lwd = 2, col = "orange3",
     xlab = "Tick", ylab = "Count", main = "Layoffs per Tick")
dev.off()

if (nrow(fail) > 0) {
  png(file.path(plot_dir, "firm_failure_diagnostics.png"), width = 1400, height = 900)
  par(mfrow = c(2, 2), mar = c(4, 4, 2, 1))

  counts <- sort(table(fail$reason), decreasing = TRUE)
  barplot(counts, col = "tomato", ylab = "Events", main = "Failure Reasons")

  plot(fail$tick, fail$cash_before_exit, pch = 16, cex = 0.6, col = "gray30",
       xlab = "Tick", ylab = "Cash Before Exit", main = "Cash Before Exit")
  abline(h = 0, lty = 2, col = "red")

  plot(fail$tick, fail$profit_this_tick, pch = 16, cex = 0.6, col = "gray30",
       xlab = "Tick", ylab = "Profit This Tick", main = "Profit at Failure")
  abline(h = 0, lty = 2, col = "red")

  # Rolling failure intensity
  max_tick <- max(events$tick)
  by_tick <- tabulate(fail$tick, nbins = max_tick)
  roll_n <- 50
  roll <- stats::filter(by_tick, rep(1 / roll_n, roll_n), sides = 1)
  plot(seq_along(by_tick), by_tick, type = "h", col = "gray70", xlab = "Tick", ylab = "Failures",
       main = "Failures per Tick (and 50-tick MA)")
  lines(seq_along(roll), roll, col = "firebrick", lwd = 2)

  dev.off()
}

cat("Wrote plots to", plot_dir, "\n")
cat("Reconstruction check:", file.path(plot_dir, "reconstruction_check.csv"), "\n")
