#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(args) >= 1) args[[1]] else "outputs/overnight"
plot_dir <- file.path(out_dir, "plots")
dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)

market <- read.csv(file.path(out_dir, "market_log.csv"))
fail <- read.csv(file.path(out_dir, "firm_failures.csv"))
expn <- read.csv(file.path(out_dir, "expansions.csv"))

market$unemployed <- market$population - market$employed

# failure reason colors
reason_cols <- c(
  negative_cash = "firebrick3",
  no_capital_units = "darkorange3",
  shell_expiry = "mediumpurple4"
)

# fallback for unseen reasons
if (nrow(fail) > 0) {
  unk <- setdiff(unique(fail$reason), names(reason_cols))
  if (length(unk) > 0) {
    for (u in unk) reason_cols[[u]] <- "gray40"
  }
}

# counts by tick/reason for rug-height marks
fail_by_tick <- NULL
if (nrow(fail) > 0) {
  fail_by_tick <- as.data.frame(table(fail$tick, fail$reason), stringsAsFactors = FALSE)
  names(fail_by_tick) <- c("tick", "reason", "n")
  fail_by_tick$tick <- as.numeric(as.character(fail_by_tick$tick))
  fail_by_tick <- fail_by_tick[fail_by_tick$n > 0, ]
}

png(file.path(plot_dir, "publication_panel.png"), width = 1800, height = 1300, res = 140)
layout(matrix(c(1,2,3), nrow = 3, byrow = TRUE), heights = c(1.2, 1.0, 0.8))
par(mar = c(3.8, 4.4, 2.4, 1.2), cex.axis = 1.0, cex.lab = 1.05)

# Panel 1: Population and unemployment count
ymax_panel1 <- max(market$population, market$unemployed, na.rm = TRUE)
plot(market$tick, market$population, type = "l", lwd = 2.4, col = "steelblue4",
     xlab = "Tick", ylab = "Count", ylim = c(0, ymax_panel1),
     main = "UrbanABM Run: Population, Unemployment, Expansion, and Firm Failures")

# expansion markers
if (nrow(expn) > 0) {
  abline(v = expn$tick, col = "gray35", lty = 2, lwd = 1.4)
  y_top <- par("usr")[4]
  text(expn$tick, rep(y_top * 0.96, nrow(expn)), labels = paste0("Exp@", expn$tick),
       srt = 90, pos = 4, cex = 0.75, col = "gray25", xpd = TRUE)
}

lines(market$tick, market$unemployed, lwd = 2.0, col = "darkgreen")

legend("topright",
       legend = c("Population", "Unemployed", "Grid Expansion"),
       col = c("steelblue4", "darkgreen", "gray35"),
       lty = c(1, 1, 2), lwd = c(2.4, 2.0, 1.4), bty = "n")

# Panel 2: Failure reasons over time (tick-wise counts)
max_tick <- max(market$tick)
plot(NA, xlim = c(min(market$tick), max_tick), ylim = c(0, max(1, ifelse(nrow(fail) > 0, max(table(fail$tick)), 1))),
     xlab = "Tick", ylab = "Failures per Tick", main = "Firm Failure Events by Reason")

if (nrow(fail_by_tick) > 0) {
  for (r in unique(fail_by_tick$reason)) {
    sub <- fail_by_tick[fail_by_tick$reason == r, ]
    points(sub$tick, sub$n, pch = 16, cex = 0.8, col = reason_cols[[r]])
    lines(sub$tick, sub$n, col = reason_cols[[r]], lwd = 1.2)
  }
  legend("topright", legend = names(reason_cols), col = unname(reason_cols), pch = 16, lty = 1, bty = "n")
}
if (nrow(expn) > 0) abline(v = expn$tick, col = "gray35", lty = 2, lwd = 1.0)

# Panel 3: Cash-before-exit and profit-at-exit scatter
plot(NA, xlim = c(min(market$tick), max_tick), ylim = c(min(-200, ifelse(nrow(fail)>0,min(fail$cash_before_exit, fail$profit_this_tick),-1)),
                                                        max(50, ifelse(nrow(fail)>0,max(fail$cash_before_exit, fail$profit_this_tick),1))),
     xlab = "Tick", ylab = "USD", main = "Exit Financials")

if (nrow(fail) > 0) {
  for (r in unique(fail$reason)) {
    sub <- fail[fail$reason == r, ]
    points(sub$tick, sub$cash_before_exit, pch = 1, cex = 0.8, col = reason_cols[[r]])
    points(sub$tick, sub$profit_this_tick, pch = 16, cex = 0.65, col = reason_cols[[r]])
  }
  abline(h = 0, col = "gray30", lty = 2)
  legend("bottomleft",
         legend = c("Cash before exit (open)", "Profit this tick (filled)"),
         pch = c(1, 16), col = c("black", "black"), bty = "n")
}
if (nrow(expn) > 0) abline(v = expn$tick, col = "gray35", lty = 2, lwd = 1.0)

dev.off()

# brief data summary for reference
summary_path <- file.path(plot_dir, "publication_panel_summary.csv")
if (nrow(fail) > 0) {
  reason_tab <- as.data.frame(table(fail$reason), stringsAsFactors = FALSE)
  names(reason_tab) <- c("reason", "count")
  reason_tab$share <- reason_tab$count / sum(reason_tab$count)
  write.csv(reason_tab, summary_path, row.names = FALSE)
} else {
  write.csv(data.frame(reason = character(), count = integer(), share = numeric()), summary_path, row.names = FALSE)
}

cat("Wrote:", file.path(plot_dir, "publication_panel.png"), "\n")
cat("Wrote:", summary_path, "\n")
