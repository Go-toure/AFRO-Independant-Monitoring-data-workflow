# Static checks that app.R keeps its server-side guards (catches an accidental
# removal when the file is edited later).  Run from the repo root.
src <- readLines("shiny_app/app.R", warn = FALSE)
ok <- 0L
check <- function(desc, cond) { if (!isTRUE(cond)) stop("FAILED: ", desc, call. = FALSE); ok <<- ok + 1L; cat("  ok -", desc, "\n") }

admin_events <- c("run_fetch","run_build","run_clean","run_upload","run_rpts","run_all","btn_stop","btn_rl_log")
for (ev in admin_events) {
  i <- grep(sprintf("observeEvent\\(input\\$%s, \\{", ev), src)
  check(paste("exactly one handler for", ev), length(i) == 1L)
  check(paste(ev, "is admin-guarded on its first line"), grepl("if \\(!is_admin\\(\\)\\) return\\(\\)", src[i + 1L]))
}
lm <- grep("load_im_data\\(\\)", src)
check("app.R never calls load_im_data() directly (only via load_scoped)",
      all(grepl("load_scoped <- function\\(\\) ac_scope_data\\(load_im_data\\(\\), user\\(\\)\\)", src[lm])))
check("startup loader waits for sign-in", any(grepl("^\\s*req\\(user\\(\\)\\)", src)))
check("log output is admin-only", any(grepl("output\\$log_txt <- renderText\\(\\{ req\\(is_admin\\(\\)\\)", src)))
check("raw-form UIs/handlers check form_ok (3 renderUI + filename + content)",
      sum(grepl("form_ok\\(form_id\\)", src)) >= 5L)
check("raw form id list is filtered by form_ok", any(grepl("vapply\\(ids, form_ok", src)))
check("AI chat handler is admin-only", any(grepl("if \\(!is_admin\\(\\)\\) \\{", src)) &&
        any(grepl("available to the regional office only", src)))
check("Pipeline panel has a stable value for nav_remove", any(grepl('Pipeline"\\), value = "pipeline"', src)))
cat(sprintf("\nAll %d static guard checks passed.\n", ok))
