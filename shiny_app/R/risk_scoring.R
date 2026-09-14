# ============================================================
# RISK SCORING ENGINE
# ============================================================
# Moved out of shiny_app/app.R during the app.R modularization pass.
# This file lives in shiny_app/R/ , which Shiny's runApp() sources
# automatically before app.R itself runs (shiny::loadSupport()), so
# no explicit source() call is needed anywhere -- everything defined
# here is available to app.R exactly as if it were still inline.
# Content is verbatim from the original app.R (byte-identical).
# ============================================================

# Risk scoring engine (mirrors intelligence report logic)
with_risk <- function(df) {
  if (!all(c("u5_present","u5_fm") %in% names(df))) return(df)
  df$u5_present <- as.numeric(df$u5_present)
  df$u5_fm      <- as.numeric(df$u5_fm)
  if (!"missed_child" %in% names(df))
    df$missed_child <- pmax(df$u5_present - df$u5_fm, 0, na.rm=FALSE)
  df$cv_d        <- ifelse(df$u5_present > 0, df$u5_fm / df$u5_present, NA_real_)
  df$missed_rate <- ifelse(df$u5_present > 0, df$missed_child / df$u5_present, NA_real_)
  has_sm <- all(c("number_of_hh_visited","care_giver_informed_sia") %in% names(df))
  df$awareness_rate <- if (has_sm)
    ifelse(as.numeric(df$number_of_hh_visited) > 0,
           as.numeric(df$care_giver_informed_sia) / as.numeric(df$number_of_hh_visited),
           NA_real_)
  else NA_real_
  df$risk_score <-
    ifelse(is.na(df$cv_d), 50,
    ifelse(df$cv_d < 0.80, 60, ifelse(df$cv_d < 0.90, 40, 20))) +
    ifelse(is.na(df$missed_rate), 0,
    ifelse(df$missed_rate > 0.20, 30, ifelse(df$missed_rate > 0.10, 15, 0))) +
    ifelse(is.na(df$awareness_rate), 0,
    ifelse(df$awareness_rate < 0.50, 20, ifelse(df$awareness_rate < 0.80, 10, 0)))
  df$risk_class <- ifelse(df$risk_score >= 70, "Critical",
                   ifelse(df$risk_score >= 50, "High",
                   ifelse(df$risk_score >= 30, "Moderate", "Low")))
  df
}
