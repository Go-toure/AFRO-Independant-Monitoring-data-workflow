#!/usr/bin/env python3
"""
im_findings_text.py - reads the monitors' free-text comments (summary1/comments) of the IM forms and turns them into counts by theme.

    python py/im_findings_text.py --only TCD,NGA     step 1: classify the comments of some countries (all countries without --only)
    python py/im_findings_text.py --model            step 2: learned model + new-theme discovery on the pooled comments of step 1

Step 1 (exact, explainable): a French / English / Portuguese list of expressions sorts every comment into themes (a comment can have several):
  REFUSAL, ABSENT, NOT_VISITED, MISSED_CHILD_REPORTED, MARKING, NO_TEAM, VACCINE_SUPPLY, SECURITY, ACCESS, COMMUNICATION, RUMOUR_BELIEF, QUALITY,
  INCENTIVE, RECOMMENDATION, AFP_SURVEILLANCE, COVERAGE_GOOD, POSITIVE;  (version 2: the last five themes were found by the clustering of step 2)
  NO_FINDING (RAS, rien a signaler, nothing to report ...), SHORT (two words or fewer), OTHER (nothing matched).
  It is checked against the numbers in the same record: do comments that mention refusal come from records with refusals counted, comments
  that mention absent children from records with absent children counted, and so on (lift = how many times more likely).
Step 2 (learned): a character n-gram model learns each theme from the step 1 labels (it copes with misspellings and mixed languages); it is tested on
  comments it has not seen, and its extra finds (comments it marks but the list missed) are checked against the same record numbers. Unmatched
  comments are grouped by TF-IDF clustering so that new themes can be named by a person and added to the list.
Output, shareable (counts only): reports/findings_text/findings_by_country_year.csv, findings_by_district.csv, findings_validation.csv, model_report.csv
Local only (the comments themselves can contain names): data/findings_local/
"""
import argparse, csv, re, time, unicodedata, json
from pathlib import Path
import numpy as np, pandas as pd, pyarrow.parquet as pq

HERE = Path(__file__).resolve().parent.parent
OUT = HERE / "reports" / "findings_text"; LOC = HERE / "data" / "findings_local"

NO_FINDING = re.compile(r"^(ras|r a s|rien a signaler|rien|neant|nul|aucun|aucune|ok|oui|non|no|nothing|nothing to report|none|nil|n a|na|nan|sans commentaire|pas de commentaire|no comment|no comments|"
                        r"no issue|no issues|no problem|no problems|pas de probleme|aucun probleme|sem novidade|sem comentarios|nada a assinalar|nada|tout va bien|c est bon|bon|bien|good|fine|all good|"
                        r"everything is fine|everything ok|rien a declarer|r a s rien|aucune observation|pas d observation|no observation|no remarks?)$")
LEX = {
 "REFUSAL": r"\b(refus\w*|rejet\w*|non ?compl\w*|recus\w*|resist\w*|boycott\w*|nao aceit\w*|ne veu\w* pas|opposi\w*|declin\w*)",
 "ABSENT": r"\b(absen\w*|ausen\w*|voyag\w*|travel\w*|champs?|au marche|le marche|market|ecole|school|farm\w*|ferme|machamba|viagem|sorti\w*|partis?|away|pas a la maison|nao estava)",
 "NOT_VISITED": r"\b(non visite\w*|pas visite\w*|jamais visite\w*|not visited|never visited|no visit\w*|unvisited|nao visit\w*|menages? (non|pas) |oublie\w*|omis\w*|skipp\w*|missed (the )?(house|household|home)|house\w* (was |were )?(missed|skipped|not visited)|pas passe\w*|non passe\w*|pas ete visite\w*)",
 "NO_TEAM": r"\b(sans equipe|aucune equipe|pas d equipe|no team|team\w* (did not|didn t|not|never)|equipe\w* (n a|na|pas|absent|retard)|retard\w*|late|atras\w*|equipa\w* (nao|ausente)|nao passou|vaccinators? (did not|not))",
 "VACCINE_SUPPLY": r"\b(rupture\w*|manque\w* (de )?(vaccin\w*|flacon\w*|materiel|marqueur\w*|craie|fournitures?)|pas de vaccin|plus de vaccin|vaccin\w* (insuffis\w*|epuis\w*|fini\w*)|insuffisan\w*|shortage|out of stock|stock ?out|no vaccines?|ran out|run out|vaccines? (finished|exhausted)|falta de vacina|sem vacina|escassez|marker|marqueur|chalk|craie|vials?|flacons?)",
 "SECURITY": r"\b(insecur\w*|securit\w*|conflit\w*|conflict\w*|armed|arme\w*|bandit\w*|attaq\w*|attack\w*|terror\w*|boko|violen\w*|guerre|war|tension\w*|inseguran\w*|ataque\w*|militar\w*|rebel\w*|kidnap\w*|enlev\w*|crise|crisis|unrest|troubles)",
 "ACCESS": r"\b(pluie\w*|rain\w*|inond\w*|flood\w*|route\w*|road\w*|boue|pont|riviere|river|inaccessib\w*|acces|access\w*|chuva\w*|estrada\w*|eloign\w*|distance|difficile\w*|difficult\w*|terrain|enclav\w*|remote|hard to reach)",
 "COMMUNICATION": r"\b(sensibili\w*|mobilis\w*|mobiliz\w*|information\w*|informe\w*|communic\w*|crieur\w*|town crier|annonc\w*|radio|affich\w*|awareness|not informed|sensibiliz\w*|comunica\w*|avis|social mobili\w*|relais|mobiliseur\w*|pas ete informe\w*)",
 "RUMOUR_BELIEF": r"\b(rumeur\w*|rumou?r\w*|religi\w*|croyance\w*|belief\w*|eglise|church|mosque\w*|desinformation|misinformation|effets? secondaires?|side effects?|steril\w*|haram|crenca\w*|fake|peur|fear\w*|mefian\w*|distrust|mistrust)",
 "QUALITY": r"\b(supervis\w*|formation|training|qualite|quality|mal (fait|rempli|execute)|badly|poorly|poor|wrong|erreur\w*|error\w*|tally|fiche|registre|incorrect\w*|not correct|mauvais\w*)",
 "INCENTIVE": r"\b(paiement\w*|payment\w*|per diem|perdiem|prime\w*|incentive\w*|argent|money|salaire\w*|salary|pagamento\w*|subsid\w*|motivation|unpaid)",
 "MISSED_CHILD_REPORTED": r"\b(non vaccin\w*|pas vaccin\w*|unvaccinated|not (been )?vaccinated|nao vacinad\w*|missed child\w*|child\w* (was|were) missed|enfants? (manque\w*|rate\w*)|criancas? (nao|sem)|zero dose)",
 "MARKING": r"\b(marqu\w*|mark(ed|ing)?|marcad\w*|marcac\w*)",
 "RECOMMENDATION": r"\b(need\w* to|should|must|needs? (more|revisit|follow)|more (sensiti\w*|supervis\w*|team\w*)|il faut|devrait|doit|faut|suggest\w*|recommand\w*|deve\w*|precisa\w*|revisit\w*|follow ?up|retourner|repasser)",
 "AFP_SURVEILLANCE": r"\b(pfa|afp|paralysie flasque|acute flaccid|vigilancia|surveillance)\b",
 "COVERAGE_GOOD": r"\b(bien couvert\w*|well covered|fully covered|completely covered|been covered|bem coberto\w*|all (the )?(children|eligible children|houses)[\w ]* (vaccinated|received|covered|visited)|tous les (enfants|menages)[\w ]* (vaccin\w*|visit\w*|couvert\w*)|todas as criancas|no missed child|aucun enfant (manque|rate))",
 "POSITIVE": r"\b(bon deroulement|bem feito|bem feita|trabalho bem|(is|was|are|going|done|doing) (going )?well|great job|doing (their|his|her) best|normalidade|bien organise|bem organizado|bon travail|bien fait|bien deroule|bien passe|bonne? (campagne|couverture|collaboration)|good (work|job|coverage|campaign)|well (done|organi[sz]ed)|excellent\w*|satisf\w*|felicit\w*|bom trabalho|parfait\w*|merci|thank\w*|success\w*|reussi\w*|sans probleme|sem problema\w*)",
}
LEXC = {k: re.compile(v) for k, v in LEX.items()}
NEG = re.compile(r"\b(no|not any|aucun\w*|zero|0|pas d|sans|nobody|none|nao ha|nao ficou)\s+(\w+\s+){0,2}(missed|manque\w*|unvaccinated|non vaccin\w*|child missed)")
THEMES = list(LEX)
# theme -> the number in the same record that should rise with it
FIELD = {"MISSED_CHILD_REPORTED": "missed", "REFUSAL": "refusal", "ABSENT": "absent", "NOT_VISITED": "missed", "NO_TEAM": "noteam"}
CAND = dict(text=("summary1/comments", "comments", "Comment"), region=("Region", "states", "state"), district=("District", "lgas", "lga"), dm=("date_monitored", "today"),
            refusal=("Total_refusal",), absent=("Total_Absent",), missed=("sum_missed_children",), noteam=("Total_Noteam",))


def norm(t):
    t = unicodedata.normalize("NFKD", str(t)).encode("ascii", "ignore").decode().lower()
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9 ]+", " ", t)).strip()


def classify(n):
    if n == "": return {"EMPTY": True}
    if NO_FINDING.match(n): return {"NO_FINDING": True}
    hit = {k: True for k, rx in LEXC.items() if rx.search(n)}
    if hit.get("MISSED_CHILD_REPORTED") and NEG.search(n): hit.pop("MISSED_CHILD_REPORTED"); hit["COVERAGE_GOOD"] = True   # "no missed child" is good news
    if hit: return hit
    return {"SHORT": True} if len(n.split()) <= 2 else {"OTHER": True}


def run(iso, name, form):
    t0 = time.time(); f = HERE / "data" / "raw" / f"{form}.parquet"
    names = pq.ParquetFile(f).schema_arrow.names
    pick = {k: next((c for c in v if c in names), None) for k, v in CAND.items()}
    if not pick["text"]: raise RuntimeError("no comment column")
    raw = pq.read_table(f, columns=sorted({c for c in pick.values() if c})).to_pandas()
    d = pd.DataFrame({k: raw[c].astype("object") for k, c in pick.items() if c}); del raw
    for k in CAND:
        if k not in d: d[k] = np.nan
    d["text"] = d["text"].astype(str).str.strip(); d = d[~d["text"].isin(["", "nan", "None", "0", "<NA>"])].copy()
    d["n"] = d["text"].map(norm); d = d[d["n"] != ""]
    uniq = pd.Series(d["n"].unique()); lab = pd.DataFrame([classify(u) for u in uniq], index=uniq).fillna(False).astype(bool)
    for c in THEMES + ["NO_FINDING", "SHORT", "OTHER"]:
        if c not in lab: lab[c] = False
    L = lab.loc[d["n"].values].reset_index(drop=True); d = d.reset_index(drop=True)
    d["year"] = pd.to_datetime(d["dm"], errors="coerce").dt.year
    for c in ("refusal", "absent", "missed", "noteam"): d[c] = pd.to_numeric(d[c], errors="coerce")
    LOC.mkdir(parents=True, exist_ok=True); OUT.mkdir(parents=True, exist_ok=True)
    loc = pd.concat([d[["n", "region", "district", "year", "refusal", "absent", "missed", "noteam"]], L[THEMES + ["NO_FINDING", "SHORT", "OTHER"]].astype(int)], axis=1)
    loc.insert(0, "iso", iso); loc.to_parquet(LOC / f"{iso.lower()}_comments.parquet", index=False)
    cols = THEMES + ["NO_FINDING", "SHORT", "OTHER"]
    cy = pd.concat([d[["year"]], L[cols]], axis=1).groupby("year").agg(comments=("OTHER", "size"), **{c: (c, "sum") for c in cols}).reset_index(); cy.insert(0, "country", name); cy.insert(0, "iso", iso)
    dd = pd.concat([d[["region", "district"]].fillna(""), L[cols]], axis=1).groupby(["region", "district"]).agg(comments=("OTHER", "size"), **{c: (c, "sum") for c in cols}).reset_index(); dd.insert(0, "country", name); dd.insert(0, "iso", iso)
    val = []
    for th, fld in FIELD.items():
        m = d[fld].notna()
        if m.sum() == 0: continue
        pos = d[fld] > 0; hit = L[th].values
        val.append(dict(iso=iso, theme=th, field=fld, mention_and_field=int((hit & pos & m).sum()), mention_no_field=int((hit & ~pos & m).sum()), nomention_and_field=int((~hit & pos & m).sum()), nomention_no_field=int((~hit & ~pos & m).sum())))
    return cy, dd, pd.DataFrame(val), dict(iso=iso, comments=len(d), seconds=round(time.time() - t0), other_pct=round(100 * L["OTHER"].mean(), 1), no_finding_pct=round(100 * L["NO_FINDING"].mean(), 1))


def merge(name, new, keys):
    p = OUT / name; new = pd.concat(new)
    old = pd.read_csv(p) if p.exists() else pd.DataFrame()
    allr = pd.concat([old[~old["iso"].isin(new["iso"])] if len(old) else old, new]); allr.to_csv(p, index=False, encoding="utf-8"); return allr


def step1(only):
    cy, dd, vv, info = [], [], [], []
    for f in csv.DictReader((HERE / "config" / "country_forms.csv").open(encoding="utf-8")):
        if only and f["country_key"] not in only: continue
        try:
            a, b, c, i = run(f["country_key"], f["country_name"], f["form_id"]); cy.append(a); dd.append(b); vv.append(c); info.append(i)
            print(f"{i['iso']} ok in {i['seconds']}s | {i['comments']:,} comments | no finding {i['no_finding_pct']}% | unmatched {i['other_pct']}%", flush=True)
        except Exception as e:
            print(f"{f['country_key']} FAILED | {type(e).__name__}: {e}", flush=True)
    if cy:
        merge("findings_by_country_year.csv", cy, ["iso"]); merge("findings_by_district.csv", dd, ["iso"]); v = merge("findings_validation_counts.csv", [x for x in vv if len(x)], ["iso"])
        g = v.groupby(["theme", "field"])[["mention_and_field", "mention_no_field", "nomention_and_field", "nomention_no_field"]].sum().reset_index()
        g["share_field_given_mention"] = (g.mention_and_field / (g.mention_and_field + g.mention_no_field)).round(3)
        g["share_field_given_no_mention"] = (g.nomention_and_field / (g.nomention_and_field + g.nomention_no_field)).round(3)
        g["lift"] = (g.share_field_given_mention / g.share_field_given_no_mention).round(2); g.to_csv(OUT / "findings_validation.csv", index=False)


def step2():
    from sklearn.feature_extraction.text import TfidfVectorizer
    from sklearn.linear_model import SGDClassifier
    from sklearn.metrics import f1_score, precision_score, recall_score
    from sklearn.cluster import MiniBatchKMeans
    parts = [pd.read_parquet(f) for f in sorted(LOC.glob("*_comments.parquet"))]
    d = pd.concat(parts, ignore_index=True); rs = np.random.RandomState(7)
    d = d[~((d.NO_FINDING == 1) & (d[THEMES].sum(axis=1) == 0))] if False else d
    d = d.drop_duplicates(["iso", "n"]).reset_index(drop=True)      # each distinct comment once per country, so common phrases do not dominate
    d = d[d.SHORT + d.NO_FINDING == 0] if False else d
    print(len(d), "distinct comments from", d.iso.nunique(), "countries", flush=True)
    s = d.sample(min(len(d), 250000), random_state=7).reset_index(drop=True)
    te = rs.rand(len(s)) < 0.2
    vec = TfidfVectorizer(analyzer="char_wb", ngram_range=(3, 5), min_df=3, max_features=200000, sublinear_tf=True, dtype=np.float32)
    Xtr = vec.fit_transform(s.n[~te]); Xte = vec.transform(s.n[te])
    rep = []
    s_all = None
    for th in ("REFUSAL", "ABSENT", "NOT_VISITED", "MISSED_CHILD_REPORTED", "MARKING", "NO_TEAM", "VACCINE_SUPPLY", "SECURITY", "ACCESS", "COMMUNICATION", "RUMOUR_BELIEF", "QUALITY", "INCENTIVE"):
        ytr, yte = s[th][~te].values, s[th][te].values
        if ytr.sum() < 50: continue
        m = SGDClassifier(loss="log_loss", alpha=2e-6, max_iter=15, tol=None, random_state=7, class_weight="balanced").fit(Xtr, ytr)
        pr = m.predict_proba(Xte)[:, 1]; pred = pr >= 0.5
        row = dict(theme=th, comments_train=int(ytr.sum()), f1_vs_list=round(f1_score(yte, pred), 3), precision_vs_list=round(precision_score(yte, pred), 3), recall_vs_list=round(recall_score(yte, pred), 3))
        # extra finds: marked by the model, missed by the list; checked against the number in the same record
        extra = (pr >= 0.9) & (yte == 0); rec = s[te].reset_index(drop=True)
        fld = FIELD.get(th)
        if fld is not None:
            rec_ok = rec[fld].notna().values; pos = (rec[fld] > 0).values
            if (extra & rec_ok).sum() >= 30:
                row.update(model_only_finds=int(extra.sum()), model_only_share_with_field=round(float(pos[extra & rec_ok].mean()), 3), base_share_with_field=round(float(pos[rec_ok & (yte == 0) & ~extra].mean()), 3))
        else: row.update(model_only_finds=int(extra.sum()))
        if row.get("model_only_finds") and len(rec[extra]):
            ex = rec[extra].n.head(40).tolist(); (LOC / f"model_only_{th.lower()}.txt").write_text("\n".join(ex), encoding="utf-8")
        rep.append(row); print(row, flush=True)
    pd.DataFrame(rep).to_csv(OUT / "model_report.csv", index=False)
    # discovery: unmatched comments of 4+ words, clustered
    o = d[(d.OTHER == 1) & (d.n.str.split().str.len() >= 4)]
    if len(o) >= 500:
        o = o.sample(min(len(o), 100000), random_state=7)
        tv = TfidfVectorizer(ngram_range=(1, 2), min_df=5, max_df=0.3, sublinear_tf=True, max_features=60000); X = tv.fit_transform(o.n)
        km = MiniBatchKMeans(n_clusters=25, random_state=7, n_init=3, batch_size=4096).fit(X); terms = np.array(tv.get_feature_names_out())
        rows, ex = [], []
        for k in range(25):
            idx = np.where(km.labels_ == k)[0]; top = terms[np.argsort(-km.cluster_centers_[k])[:10]]
            rows.append(dict(cluster=k, comments=len(idx), top_terms=" | ".join(top), countries=int(o.iso.iloc[idx].nunique())))
            ex += [f"[{k}] {t}" for t in o.n.iloc[idx][:3]]
        pd.DataFrame(rows).sort_values("comments", ascending=False).to_csv(OUT / "unmatched_clusters.csv", index=False)
        (LOC / "unmatched_cluster_examples.txt").write_text("\n".join(ex), encoding="utf-8")
        print(f"{len(o):,} unmatched comments grouped into 25 clusters", flush=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("--only", default=""); ap.add_argument("--model", action="store_true"); a = ap.parse_args()
    if a.model: step2()
    else: step1({x.strip().upper() for x in a.only.split(",") if x.strip()})
