#!/usr/bin/env Rscript
out_dir <- "outputs/overnight/plots"
rc <- read.csv(file.path(out_dir, "churn_reason_counts.csv"))
re <- read.csv(file.path(out_dir, "churn_reason_effects.csv"))
tc <- read.csv(file.path(out_dir, "churn_trigger_counts.csv"))
te <- read.csv(file.path(out_dir, "churn_trigger_effects.csv"))

png(file.path(out_dir, "churn_reason_breakdown.png"), width=1600, height=900, res=140)
par(mfrow=c(1,2), mar=c(8,4,2,1))

# counts
ord <- order(rc$switch_events, decreasing=TRUE)
barplot(rc$switch_events[ord], names.arg=rc$reason[ord], las=2, col="steelblue4",
        ylab="Switch Events", main="Switch Events by Reason")

# effect ratios
ord2 <- order(re$present_absent_ratio, decreasing=TRUE)
barplot(re$present_absent_ratio[ord2], names.arg=re$reason[ord2], las=2, col="firebrick3",
        ylab="Mean |Δsales| ratio", main="Sales-Swing Ratio When Reason Present")
abline(h=1, lty=2, col="gray30")

dev.off()

png(file.path(out_dir, "churn_trigger_breakdown.png"), width=1400, height=700, res=140)
par(mfrow=c(1,2), mar=c(6,4,2,1))
barplot(tc$switch_events, names.arg=tc$trigger, col="darkgreen", ylab="Switch Events", main="Switch Events by Trigger")
barplot(te$present_absent_ratio, names.arg=te$trigger, col="darkorange3", ylab="Mean |Δsales| ratio", main="Sales-Swing Ratio by Trigger")
abline(h=1, lty=2, col="gray30")
dev.off()

cat('Wrote churn_reason_breakdown.png and churn_trigger_breakdown.png\n')
