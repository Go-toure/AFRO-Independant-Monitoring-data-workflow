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
      all(grepl("load_scoped <- function\\(\\) \\{ if \\(is.null\\(user\\(\\)\\)\\) return\\(NULL\\); ac_scope_data\\(load_im_data\\(\\), user\\(\\)\\) \\}", src[lm])))
i0 <- grep("# ── Load on startup", src, fixed = TRUE)
check("startup loader waits for sign-in (req(user()) is the first statement of the loader)",
      length(i0) == 1L && grepl("^\\s*observe\\(\\{", src[i0 + 1L]) && grepl("^\\s*req\\(user\\(\\)\\)", src[i0 + 2L]))
check("log lines are only read for admins", any(grepl("observeEvent\\(user\\(\\), \\{ if \\(is_admin\\(\\)\\) rv_log\\(get_log_lines\\(\\)\\)", src)))
check("raw-download build folder is cleaned up after the copy", any(grepl('startsWith\\(basename\\(wd\\), "im_dl_"\\)', src)))
check("log output is admin-only", any(grepl("output\\$log_txt <- renderText\\(\\{ req\\(is_admin\\(\\)\\)", src)))
check("raw-form UIs/handlers check form_ok (3 renderUI + filename + content)",
      sum(grepl("form_ok\\(form_id\\)", src)) >= 5L)
check("raw form id list is filtered by form_ok", any(grepl("vapply\\(ids, form_ok", src)))
check("AI chat handler is admin-only", any(grepl("if \\(!is_admin\\(\\)\\) \\{", src)) &&
        any(grepl("available to the regional office only", src)))
check("Pipeline panel has a stable value for nav_remove", any(grepl('Pipeline"\\), value = "pipeline"', src)))

# ── country "My data" tab ────────────────────────────────────────────────────
cr_src <- readLines("shiny_app/R/country_run.R", warn = FALSE)
check("Pipeline tab has an admin block and a country block", any(grepl('div\\(id = "pl_admin_block"', src)) && any(grepl('div\\(id = "pl_country_block", style = "display:none;"', src)))
check("country runner is wired into the server", any(grepl("cr_session_init\\(input, output, session, auth", src)))
check("country run/stop handlers require a country user",
      sum(grepl("if \\(!is_country\\(\\)\\) return\\(\\)", cr_src)) >= 2L)
check("country run checks the chosen form against the user's own forms", any(grepl("!auth\\$form_ok\\(fid\\)", cr_src)))
check("country downloads re-check role, run status and form",
      any(grepl("is_country\\(\\) && identical\\(cr\\$status, \"ok\"\\)", cr_src)) && any(grepl("auth\\$form_ok\\(cr\\$form\\)", cr_src)))
check("runner is started without the access codes / API key",
      any(grepl('IM_ADMIN_CODES = ""', cr_src)) && any(grepl('IM_COUNTRY_CODES = ""', cr_src)) && any(grepl('ANTHROPIC_API_KEY = ""', cr_src)))
check("only the filtered runner stdout is shown (stderr goes to a private file)",
      any(grepl("runner_stderr.txt", cr_src)) && any(grepl("add_log\\(strsplit", cr_src)) && any(grepl("cr_clean_lines\\(lines\\)", cr_src)))
check("no direct SharePoint access from the country module", !any(grepl("sp_get_graph_token|sp_download_file|sharepoint_credentials", cr_src)))

# ── raw download: browser-supplied values are validated ─────────────────────
check("year/response observers only accept valid values",
      any(grepl("if \\(\\.rd_year_arg_ok\\(input\\$dl_raw_year\\)\\)", src)) && any(grepl("if \\(\\.rd_text_ok\\(input\\$dl_raw_response\\)\\)", src)))
check("download filename + content validate form/format/year/text (2 places each)",
      sum(grepl("\\.rd_year_ok\\(year_arg\\)", src)) >= 2L)
check("pre-sign-in outputs wait for a user",
      any(grepl("last_run_info_r <- reactive\\(\\{ req\\(user\\(\\)\\)", src)))
rd <- readLines("shiny_app/R/data_download_raw.R", warn = FALSE)
sp <- readLines("shiny_app/R/data_source_sharepoint.R", warn = FALSE)
check("build_form_download validates its inputs", any(grepl("Invalid download request", rd)))
check("list_available_* validate form id", sum(grepl("\\.rd_form_ok\\(form_id\\)", rd)) >= 4L)
check("every SharePoint helper uses sp_path_ok", sum(grepl("if \\(!sp_path_ok\\(", sp)) == 3L)

ac_src <- readLines("shiny_app/R/access_control.R", warn = FALSE)
check("country users are sent to the My data tab after sign-in",
      any(grepl('bslib::nav_select\\("nav", "pipeline"', ac_src)) && any(grepl('id = "nav"', src)))

cat(sprintf("\nAll %d static guard checks passed.\n", ok))
