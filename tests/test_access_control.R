# Offline tests for shiny_app/R/access_control.R  (plain base R, no packages).
# Run from the repo root:  Rscript tests/test_access_control.R
CONFIG_DIR <- "config"
source("shiny_app/R/access_control.R")

n_ok <- 0L
check <- function(desc, cond) {
  if (!isTRUE(cond)) stop("FAILED: ", desc, call. = FALSE)
  n_ok <<- n_ok + 1L
  cat("  ok -", desc, "\n")
}

map <- ac_country_forms()
cat("country_forms.csv\n")
check("34 countries/forms loaded", nrow(map) == 34L)
check("form ids unique", !anyNA(map$form_id) && !any(duplicated(map$form_id)))
check("country keys unique", !any(duplicated(map$country_key)))
check("names are upper case", all(map$country_name == toupper(map$country_name)))

cat("secret parsing\n")
check("admin codes split on ; and newline", identical(ac_admin_codes(" A1 ; B2\nC3 "), c("A1", "B2", "C3")))
cc <- ac_country_codes("AGO=aaa;NGA+GHA=bbb; bogus ;=x;ZMB=")
check("country codes: valid pairs only", length(cc) == 2L)
check("country code keys", identical(cc[[2]]$keys, c("NGA", "GHA")) && cc[[1]]$code == "aaa")
check("mode: nothing set on Windows -> open", ac_mode("", "", "", "windows") == "open")
check("mode: nothing set on a server -> unconfigured (nobody)", ac_mode("", "", "", "unix") == "unconfigured")
check("mode: explicit open on a server", ac_mode("open", "", "", "unix") == "open" && ac_mode(" OPEN ", "", "", "unix") == "open")
check("mode: enforced with admin only", ac_mode("", "x", "", "unix") == "enforced")
check("mode: enforced with country only", ac_mode("", "", "AGO=abc", "windows") == "enforced")
check("mode: malformed secret still enforces (never opens)", ac_mode("", "garbage", "", "windows") == "enforced")
check("mode: secrets override explicit open", ac_mode("open", "x", "", "unix") == "enforced")

cat("constant-time equal\n")
check("equal", ac_ct_equal("Abc-123", "Abc-123"))
check("different", !ac_ct_equal("Abc-123", "Abc-124"))
check("different length", !ac_ct_equal("Abc", "Abc-1"))
check("prefix is not equal", !ac_ct_equal("Abc-1", "Abc"))
check("empty vs non-empty", !ac_ct_equal("", "a"))
check("utf-8", ac_ct_equal("café", "café") && !ac_ct_equal("café", "cafe"))

cat("authenticate\n")
admin <- c("ADMIN-CODE-001", "ADMIN-CODE-002")
ctry  <- ac_country_codes("AGO=ang-code-0001;NGA+GHA=multi-code-001;ZZZ=ghost-code-001")
au <- function(code) ac_authenticate(code, admin, ctry, map, mode = "enforced")
check("admin code -> admin", identical(au("ADMIN-CODE-002")$role, "admin"))
check("admin has no restriction lists", is.null(au("ADMIN-CODE-001")$forms) && is.null(au("ADMIN-CODE-001")$countries))
u <- au("ang-code-0001")
check("country code -> country", identical(u$role, "country"))
check("Angola scope", identical(u$countries, "ANGOLA") && identical(u$forms, "10267"))
m <- au("multi-code-001")
check("multi-country code", identical(m$countries, c("GHANA", "NIGERIA")) && identical(m$forms, c("3550", "7178")))
check("wrong code rejected", is.null(au("nope")))
check("empty code rejected", is.null(au("")) && is.null(au("   ")) && is.null(au(NULL)) && is.null(au(NA)))
check("code is case sensitive", is.null(au("admin-code-001")) && is.null(au("ANG-CODE-0001")))
check("code for unknown country key refused", is.null(au("ghost-code-001")))
check("whitespace around code is trimmed", identical(au("  ang-code-0001 ")$role, "country"))
check("a country code is never admin", !identical(au("ang-code-0001")$role, "admin"))
check("'KEY=CODE' text itself is not a code", is.null(au("AGO=ang-code-0001")))
check("open mode: any non-empty code -> admin",
      identical(ac_authenticate("x", character(), list(), map, mode = "open")$role, "admin"))
check("open mode: empty code still rejected", is.null(ac_authenticate("", character(), list(), map, mode = "open")))
check("unconfigured mode: nobody, not even with a 'valid' code",
      is.null(ac_authenticate("ADMIN-CODE-001", admin, ctry, map, mode = "unconfigured")))
check("garbage mode string: nobody", is.null(ac_authenticate("ADMIN-CODE-001", admin, ctry, map, mode = "whatever")))
check("over-long code rejected quickly", is.null(au(strrep("a", 5000))) && is.null(au(strrep("é", 100))))
only_country <- function(code) ac_authenticate(code, character(), ctry, map, mode = "enforced")
check("country-only config: no way in as admin", !identical(only_country("ADMIN-CODE-001")$role, "admin") && is.null(only_country("ADMIN-CODE-001")))
check("country-only config: country code still works", identical(only_country("ang-code-0001")$role, "country"))

cat("scoping\n")
df <- data.frame(country = c("ANGOLA", "NIGERIA", "angola ", NA, "GHANA", "CONGO"),
                 v = 1:6, stringsAsFactors = FALSE)
check("admin sees everything", nrow(ac_scope_data(df, au("ADMIN-CODE-001"))) == 6L)
sc <- ac_scope_data(df, u)
check("Angola user sees only Angola (case/space tolerant)", identical(sc$v, c(1L, 3L)))
check("multi user sees Ghana + Nigeria", identical(ac_scope_data(df, m)$v, c(2L, 5L)))
check("CONGO user does not get DR Congo / Angola rows",
      identical(ac_scope_data(df, ac_authenticate("c-code-long-enough", character(), list(list(keys = "COG", code = "c-code-long-enough")), map, mode = "enforced"))$v, 6L))
check("NA country never matches", !anyNA(sc$country))
check("no user -> NULL (nothing loaded)", is.null(ac_scope_data(df, NULL)))
check("NULL data stays NULL", is.null(ac_scope_data(NULL, u)))
check("no country column -> zero rows for a country user", nrow(ac_scope_data(data.frame(x = 1:3), u)) == 0L)
check("no country column -> admin unaffected", nrow(ac_scope_data(data.frame(x = 1:3), au("ADMIN-CODE-001"))) == 3L)
check("country user with empty scope -> zero rows",
      nrow(ac_scope_data(df, list(role = "country", countries = character()))) == 0L)
check("malformed role -> treated as country (zero rows)",
      nrow(ac_scope_data(df, list(role = "root", countries = character()))) == 0L)

cat("form access\n")
check("admin any form", ac_form_ok(au("ADMIN-CODE-001"), "4498") && ac_form_ok(au("ADMIN-CODE-001"), 123))
check("country own form", ac_form_ok(u, "10267") && ac_form_ok(u, 10267))
check("country other form refused", !ac_form_ok(u, "7178") && !ac_form_ok(u, "4498"))
check("multi-country forms", ac_form_ok(m, "3550") && ac_form_ok(m, "7178") && !ac_form_ok(m, "10267"))
check("no user refused", !ac_form_ok(NULL, "10267"))
check("NULL / NA / vector form id refused",
      !ac_form_ok(u, NULL) && !ac_form_ok(u, NA) && !ac_form_ok(u, c("10267", "7178")))
check("partial id does not match", !ac_form_ok(u, "1026") && !ac_form_ok(u, "102670") && !ac_form_ok(u, ""))
check("is_admin", ac_is_admin(au("ADMIN-CODE-001")) && !ac_is_admin(u) && !ac_is_admin(NULL))

cat("code hygiene\n")
cl <- ac_clean_config(c("short", "ADMIN-CODE-001", "ADMIN-CODE-001", strrep("x", 200)),
                      ac_country_codes("AGO=tiny;NGA=shared-code-123;GHA=shared-code-123;ZMB=ADMIN-CODE-001;KEN=keny-code-1234"))
check("short/long/duplicate admin codes dropped", identical(cl$admin, "ADMIN-CODE-001"))
check("only the clean unique country code survives", length(cl$country) == 1L && cl$country[[1]]$keys == "KEN")
check("problems are described", length(cl$problems) >= 3L && !any(grepl("ADMIN-CODE|shared-code|keny", cl$problems)))
check("a code shared by two countries opens neither",
      is.null(ac_authenticate("shared-code-123", "ADMIN-CODE-001", ac_country_codes("NGA=shared-code-123;GHA=shared-code-123"), map, mode = "enforced")))
check("a country code equal to an admin code gives admin only (not country)",
      identical(ac_authenticate("ADMIN-CODE-001", "ADMIN-CODE-001", ac_country_codes("NGA=ADMIN-CODE-001"), map, mode = "enforced")$role, "admin"))
check("short code in config can never be used",
      is.null(ac_authenticate("tiny", character(), ac_country_codes("AGO=tiny"), map, mode = "enforced")))

cat("brute-force lock\n")
check("no lock before a failure", ac_lock_seconds(0) == 0)
check("lock doubles", identical(sapply(1:5, ac_lock_seconds), c(1, 2, 4, 8, 16)))
check("lock capped at 30 s", ac_lock_seconds(20) == 30)
check("no Sys.sleep based throttle left", !exists("ac_throttle_failure"))

cat(sprintf("\nAll %d checks passed.\n", n_ok))
