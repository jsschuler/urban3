#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(args) >= 1) args[[1]] else "outputs/overnight"
plot_dir <- file.path(out_dir, "plots")
dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)

market <- read.csv(file.path(out_dir, "market_log.csv"))
events <- read.csv(file.path(out_dir, "tick_events.csv"))
fail <- read.csv(file.path(out_dir, "firm_failures.csv"))

# Merge key series
x <- merge(
  market[, c("tick", "population", "employed", "active_firms", "realized_sales", "mean_commercial_rent")],
  events,
  by = "tick",
  all.x = TRUE
)
x[is.na(x)] <- 0
x$d_pop <- c(NA, diff(x$population))

# Rolling windows for stress detection
roll_sum <- function(v, k = 50) as.numeric(stats::filter(v, rep(1, k), sides = 1))

x$roll_layoffs_50 <- roll_sum(x$layoffs, 50)
x$roll_failures_50 <- roll_sum(x$firm_exits, 50)
x$roll_immigrants_50 <- roll_sum(x$immigrants, 50)

# contraction windows based on 50-tick population drop
W <- 50
n <- nrow(x)
win <- data.frame(start_tick = integer(), end_tick = integer(),
                  pop_change = numeric(), employed_change = numeric(),
                  firms_change = numeric(), sales_change = numeric(),
                  exits = numeric(), entries = numeric(), layoffs = numeric(),
                  hires = numeric(), immigrants = numeric(), failures_logged = numeric(),
                  mean_com_rent_change = numeric())

for (i in 1:(n - W)) {
  j <- i + W
  pop_ch <- x$population[j] - x$population[i]
  if (pop_ch <= -25) {
    sl <- i:j
    win <- rbind(win, data.frame(
      start_tick = x$tick[i],
      end_tick = x$tick[j],
      pop_change = pop_ch,
      employed_change = x$employed[j] - x$employed[i],
      firms_change = x$active_firms[j] - x$active_firms[i],
      sales_change = x$realized_sales[j] - x$realized_sales[i],
      exits = sum(x$firm_exits[sl]),
      entries = sum(x$firm_entries[sl]),
      layoffs = sum(x$layoffs[sl]),
      hires = sum(x$hires[sl]),
      immigrants = sum(x$immigrants[sl]),
      failures_logged = if (nrow(fail) == 0) 0 else sum(fail$tick >= x$tick[i] & fail$tick <= x$tick[j]),
      mean_com_rent_change = x$mean_commercial_rent[j] - x$mean_commercial_rent[i]
    ))
  }
}

# keep top distinct windows by drop magnitude
if (nrow(win) > 0) {
  win <- win[order(win$pop_change), ]
  keep <- logical(nrow(win))
  last_end <- -Inf
  for (r in seq_len(nrow(win))) {
    if (win$start_tick[r] > last_end) {
      keep[r] <- TRUE
      last_end <- win$end_tick[r]
    }
  }
  top_win <- win[keep, ]
  top_win <- head(top_win, 8)
} else {
  top_win <- win
}

write.csv(top_win, file.path(plot_dir, "contraction_windows.csv"), row.names = FALSE)

# plot 1: state with failure bursts and contraction windows
png(file.path(plot_dir, "contraction_annotated.png"), width = 1600, height = 1000)
par(mfrow = c(3, 1), mar = c(4, 4, 2, 1))

plot(x$tick, x$population, type = "l", lwd = 2, col = "steelblue",
     xlab = "Tick", ylab = "Population", main = "Population with Contraction Windows")
if (nrow(top_win) > 0) {
  for (k in seq_len(nrow(top_win))) {
    rect(top_win$start_tick[k], par("usr")[3], top_win$end_tick[k], par("usr")[4],
         col = rgb(1, 0, 0, 0.08), border = NA)
  }
}
lines(x$tick, x$population, col = "steelblue", lwd = 2)

plot(x$tick, x$roll_failures_50, type = "l", lwd = 2, col = "firebrick",
     xlab = "Tick", ylab = "50-tick sum", main = "Firm Exits and Layoffs (50-tick sums)")
lines(x$tick, x$roll_layoffs_50, col = "darkorange", lwd = 2)
legend("topright", legend = c("firm_exits", "layoffs"), col = c("firebrick", "darkorange"), lwd = 2, bty = "n")

plot(x$tick, x$roll_immigrants_50, type = "l", lwd = 2, col = "darkgreen",
     xlab = "Tick", ylab = "50-tick sum", main = "Immigration Pressure (50-tick sum)")

if (nrow(fail) > 0) {
  # small rug of failure times
  rug(fail$tick, col = rgb(0.5, 0, 0, 0.4))
}

dev.off()

# plot 2: waterfall-like decomposition for top windows
if (nrow(top_win) > 0) {
  png(file.path(plot_dir, "contraction_window_decomp.png"), width = 1600, height = 1000)
  m <- as.matrix(top_win[, c("entries", "exits", "hires", "layoffs", "immigrants")])
  rownames(m) <- paste0("[", top_win$start_tick, ",", top_win$end_tick, "]")
  barplot(t(m), beside = TRUE,
          col = c("darkgreen", "firebrick", "dodgerblue4", "orange3", "purple4"),
          las = 2, cex.names = 0.8,
          main = "Top Contraction Windows: Event Totals",
          ylab = "Count")
  legend("topright", legend = colnames(m),
         fill = c("darkgreen", "firebrick", "dodgerblue4", "orange3", "purple4"), bty = "n")
  dev.off()
}

cat("Wrote:", file.path(plot_dir, "contraction_windows.csv"), "\n")
cat("Wrote:", file.path(plot_dir, "contraction_annotated.png"), "\n")
if (nrow(top_win) > 0) cat("Wrote:", file.path(plot_dir, "contraction_window_decomp.png"), "\n")
