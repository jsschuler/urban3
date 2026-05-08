#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(args) >= 1) args[[1]] else "outputs/overnight"
plot_dir <- file.path(out_dir, "plots")
dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)

x <- read.csv(file.path(out_dir, "firm_sales_by_tick.csv"))
fail_path <- file.path(out_dir, "firm_failures.csv")
fail <- if (file.exists(fail_path)) read.csv(fail_path) else data.frame()

# reduce overplot by showing active periods for line plot
xa <- x[x$active == 1, ]

# 1) all-firm line trends
png(file.path(plot_dir, "firm_sales_all_lines.png"), width = 1800, height = 1000, res = 140)
par(mar = c(4, 4, 2, 1))
plot(NA,
     xlim = range(x$tick),
     ylim = c(0, max(x$realized_sales, na.rm = TRUE)),
     xlab = "Tick", ylab = "Realized Sales",
     main = "Per-Firm Sales Trends (All Firms, Active Periods)")
for (fid in unique(xa$firm_id)) {
    s <- xa[xa$firm_id == fid, c("tick", "realized_sales")]
    lines(s$tick, s$realized_sales, col = rgb(0.2, 0.4, 0.8, 0.15), lwd = 1)
}
# overlay per-firm exit marker directly on each terminating line
if (nrow(fail) > 0) {
    reason_cols <- c(
        negative_cash = "firebrick3",
        no_capital_units = "darkorange3",
        shell_expiry = "mediumpurple4"
    )
    unk <- setdiff(unique(fail$reason), names(reason_cols))
    if (length(unk) > 0) for (u in unk) reason_cols[[u]] <- "gray35"
    for (i in seq_len(nrow(fail))) {
        fid <- fail$firm_id[i]
        tt <- fail$tick[i]
        rr <- fail$reason[i]
        y <- x$realized_sales[x$firm_id == fid & x$tick == tt]
        if (length(y) == 0) next
        points(tt, y[1], pch = 16, cex = 0.7, col = reason_cols[[rr]])
    }
    legend("topright", legend = names(reason_cols), col = unname(reason_cols), lty = 1, lwd = 2, bty = "n", cex = 0.85)
}
dev.off()

# 2) heatmap: firm_id x tick with realized sales intensity
# cast to matrix
firms <- sort(unique(x$firm_id))
ticks <- sort(unique(x$tick))
mat <- matrix(0, nrow = length(firms), ncol = length(ticks),
              dimnames = list(firms, ticks))
idx_f <- match(x$firm_id, firms)
idx_t <- match(x$tick, ticks)
mat[cbind(idx_f, idx_t)] <- x$realized_sales

png(file.path(plot_dir, "firm_sales_heatmap.png"), width = 1800, height = 1100, res = 140)
par(mar = c(4, 5, 2, 2))
# transpose for image x=tick, y=firm
image(x = ticks, y = seq_along(firms), z = t(mat),
      xlab = "Tick", ylab = "Firm (sorted by ID)",
      main = "Per-Firm Realized Sales Heatmap",
      col = hcl.colors(128, "YlOrRd", rev = FALSE), useRaster = TRUE)
yt <- pretty(seq_along(firms))
yt <- yt[yt >= 1 & yt <= length(firms)]
axis(2, at = yt, labels = firms[round(yt)], las = 2, cex.axis = 0.7)
# overlay firm-specific exit points by reason
if (nrow(fail) > 0) {
    reason_cols <- c(
        negative_cash = "firebrick3",
        no_capital_units = "darkorange3",
        shell_expiry = "mediumpurple4"
    )
    unk <- setdiff(unique(fail$reason), names(reason_cols))
    if (length(unk) > 0) for (u in unk) reason_cols[[u]] <- "gray35"
    yfirm <- match(fail$firm_id, firms)
    ok <- !is.na(yfirm)
    points(fail$tick[ok], yfirm[ok], pch = 4, cex = 0.55, lwd = 1.0, col = reason_cols[fail$reason[ok]])
}
dev.off()

# 3) median + quantiles across active firms at each tick
ticks_u <- sort(unique(xa$tick))
qmat <- t(sapply(ticks_u, function(tt) {
    v <- xa$realized_sales[xa$tick == tt]
    c(q10 = as.numeric(quantile(v, 0.1)),
      q50 = as.numeric(quantile(v, 0.5)),
      q90 = as.numeric(quantile(v, 0.9)))
}))
qdf <- data.frame(tick = ticks_u, qmat)

png(file.path(plot_dir, "firm_sales_quantiles.png"), width = 1600, height = 900, res = 140)
par(mar = c(4, 4, 2, 1))
plot(qdf$tick, qdf$q50, type = "l", lwd = 2.5, col = "steelblue4",
     ylim = c(min(qdf$q10, na.rm = TRUE), max(qdf$q90, na.rm = TRUE)),
     xlab = "Tick", ylab = "Sales", main = "Across-Firm Sales Distribution (Active Firms)")
lines(qdf$tick, qdf$q10, col = "gray40", lwd = 1.5, lty = 2)
lines(qdf$tick, qdf$q90, col = "gray40", lwd = 1.5, lty = 2)
legend("topright", legend = c("Median", "10th/90th pct"), col = c("steelblue4", "gray40"), lty = c(1,2), lwd = c(2.5,1.5), bty = "n")
dev.off()

write.csv(data.frame(n_firms = length(firms), n_ticks = length(ticks), max_sales = max(x$realized_sales, na.rm = TRUE)),
          file.path(plot_dir, "firm_sales_summary.csv"), row.names = FALSE)

cat("Wrote plots to", plot_dir, "\n")
