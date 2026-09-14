Subject: Update to AFRO_LQAS_data_c.csv on SharePoint — Absence/Non-Compliance reason columns restored + new data dictionary

Hi all,

A quick heads-up for anyone whose pipeline or dashboard reads **AFRO_LQAS_data_c.csv** from the GISWORKSPACE Data Repository (Shared Documents/7. SIA_Data/Data Repository). I refreshed that file today and it now carries columns that had quietly gone missing from the copy that was sitting on SharePoint.

**What changed**

The version of AFRO_LQAS_data_c.csv that had been on SharePoint predated the detailed Absence/Non-Compliance reason breakdown in the LQAS processing pipeline, so those columns were never making it into the shared file even though the pipeline itself has supported them for a while. The refreshed file restores all 16 of them:

- Absence reasons (6): abs_reason_farm, abs_reason_market, abs_reason_school, abs_reason_in_playground, abs_reason_travelled, abs_reason_other
- Non-Compliance reasons (10): nc_reason_religious_cultural, nc_reason_vaccines_safety, nc_reason_no_felt_need, nc_reason_too_many_rnd, nc_reason_no_care_giver_consent, nc_reason_child_sick, nc_reason_covid_19, nc_reason_poliofree, nc_reason_nopvconcern, nc_reason_others

Everything else in the file is unchanged — same 60 columns overall, same structure, just these filled back in.

**New: a companion data dictionary**

Going forward, every time this file is refreshed, a second file — **AFRO_LQAS_data_c_dictionary.xlsx** — will be updated right next to it in the same SharePoint folder. It has three tabs:

- Overview — counts of columns added/removed/changed vs. the previous version
- Changes_vs_Previous — the specific columns that changed, if any (check this one first)
- Full_Dictionary — every current column, its type, an example value, and a short description

If your pipeline hardcodes a column list from AFRO_LQAS_data_c.csv, it's worth glancing at the Changes_vs_Previous tab after each refresh rather than finding out the hard way.

**Links**

- AFRO_LQAS_data_c.csv: https://worldhealthorg.sharepoint.com/sites/AF-pep/GISWORKSPACE/_layouts/15/Doc.aspx?sourcedoc=%7B0677B038-32D9-4B06-847E-F597DF315ABA%7D&file=AFRO_LQAS_data_c.csv&action=default&mobileredirect=true
- AFRO_LQAS_data_c_dictionary.xlsx: https://worldhealthorg.sharepoint.com/sites/AF-pep/GISWORKSPACE/_layouts/15/Doc.aspx?sourcedoc=%7B14B96F01-350B-4584-940B-7E5C9A33F92B%7D&file=AFRO_LQAS_data_c_dictionary.xlsx&action=default&mobileredirect=true

Happy to walk through any of this if it affects your own pipeline — just let me know.

Best,
Gorgui
