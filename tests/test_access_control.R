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
check("mode open when nothing set", ac_mode(character(), list()) == "open")
check("mode enforced with admin only", ac_mode("x", list()) == "enforced")
check("mode enforced with country only", ac_mode(character(), cc) == "enforced")

cat("constant-time equal\n")
check("equal", ac_ct_equal("Abc-123", "Abc-123"))
check("different", !ac_ct_equal("Abc-123", "Abc-124"))
check("different length", !ac_ct_equal("Abc", "Abc-1"))
check("prefix is not equal", !ac_ct_equal("Abc-1", "Abc"))
check("empty vs non-empty", !ac_ct_equal("", "a"))
check("utf-8", ac_ct_equal("café", "café") && !ac_ct_equal("café", "cafe"))

cat("authenticate\n")
admin <- c("ADMIN-1", "ADMIN-2")
ctry  <- ac_country_codes("AGO=ang-code;NGA+GHA=multi-code;ZZZ=ghost-code")
au <- function(code) ac_authenticate(code, admin, ctry, map)
check("admin code -> admin", identical(au("ADMIN-2")$role, "admin"))
check("admin has no restriction lists", is.null(au("ADMIN-1")$forms) && is.null(au("ADMIN-1")$countries))
u <- au("ang-code")
check("country code -> country", identical(u$role, "country"))
check("Angola scope", identical(u$countries, "ANGOLA") && identical(u$forms, "10267"))
m <- au("multi-code")
check("multi-country code", identical(m$countries, c("GHANA", "NIGERIA")) && identical(m$forms, c("3550", "7178")))
check("wrong code rejected", is.null(au("nope")))
check("empty code rejected", is.null(au("")) && is.null(au("   ")) && is.null(au(NULL)) && is.null(au(NA)))
check("code is case sensitive", is.null(au("admin-1")) && is.null(au("ANG-CODE")))
check("code for unknown country key refused", is.null(au("ghost-code")))
check("whitespace around code is trimmed", identical(au("  ang-code ")$role, "country"))
check("a country code is never admin", !identical(au("ang-code")$role, "admin"))
check("'KEY=CODE' text itself is not a code", is.null(au("AGO=ang-code")))
check("open mode: any non-empty code -> admin",
      identical(ac_authenticate("x", character(), list(), map)$role, "admin"))
check("open mode: empty code still rejected", is.null(ac_authenticate("", character(), list(), map)))
only_country <- function(code) ac_authenticate(code, character(), ctry, map)
check("country-only config: no way in as admin", !identical(only_country("ADMIN-1")$role, "admin") && is.null(only_country("ADMIN-1")))
check("country-only config: country code still works", identical(only_country("ang-code")$role, "country"))

cat("scoping\n")
df <- data.frame(country = c("ANGOLA", "NIGERIA", "angola ", NA, "GHANA", "CONGO"),
                 v = 1:6, stringsAsFactors = FALSE)
check("admin sees everything", nrow(ac_scope_data(df, au("ADMIN-1"))) == 6L)
sc <- ac_scope_data(df, u)
check("Angola user sees only Angola (case/space tolerant)", identical(sc$v, c(1L, 3L)))
check("multi user sees Ghana + Nigeria", identical(ac_scope_data(df, m)$v, c(2L, 5L)))
check("CONGO user does not get DR Congo / Angola rows",
      identical(ac_scope_data(df, ac_authenticate("c", character(), list(list(keys = "COG", code = "c")), map))$v, 6L))
check("NA country never matches", !anyNA(sc$country))
check("no user -> NULL (nothing loaded)", is.null(ac_scope_data(df, NULL)))
check("NULL data stays NULL", is.null(ac_scope_data(NULL, u)))
check("no country column -> zero rows for a country user", nrow(ac_scope_data(data.frame(x = 1:3), u)) == 0L)
check("no country column -> admin unaffected", nrow(ac_scope_data(data.frame(x = 1:3), au("ADMIN-1"))) == 3L)
check("country user with empty scope -> zero rows",
      nrow(ac_scope_data(df, list(role = "country", countries = character()))) == 0L)
check("malformed role -> treated as country (zero rows)",
      nrow(ac_scope_data(df, list(role = "root", countries = character()))) == 0L)

cat("form access\n")
check("admin any form", ac_form_ok(au("ADMIN-1"), "4498") && ac_form_ok(au("ADMIN-1"), 123))
check("country own form", ac_form_ok(u, "10267") && ac_form_ok(u, 10267))
check("country other form refused", !ac_form_ok(u, "7178") && !ac_form_ok(u, "4498"))
check("multi-country forms", ac_form_ok(m, "3550") && ac_form_ok(m, "7178") && !ac_form_ok(m, "10267"))
check("no user refused", !ac_form_ok(NULL, "10267"))
check("NULL / NA / vector form id refused",
      !ac_form_ok(u, NULL) && !ac_form_ok(u, NA) && !ac_form_ok(u, c("10267", "7178")))
check("partial id does not match", !ac_form_ok(u, "1026") && !ac_form_ok(u, "102670") && !ac_form_ok(u, ""))
check("is_admin", ac_is_admin(au("ADMIN-1")) && !ac_is_admin(u) && !ac_is_admin(NULL))

cat("throttle\n")
.ac_state$fails <- numeric()
d1 <- ac_throttle_failure(now = 1000, sleep = FALSE)
d2 <- ac_throttle_failure(now = 1001, sleep = FALSE)
check("delay grows with recent failures", d2 > d1 && d1 > 0)
for (i in 1:40) d <- ac_throttle_failure(now = 1002, sleep = FALSE)
check("delay capped at 3 s", d == 3)
check("old failures expire", ac_throttle_failure(now = 5000, sleep = FALSE) == 0.25)

cat(sprintf("\nAll %d checks passed.\n", n_ok))
