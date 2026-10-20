#!/usr/bin/env python3
"""
analyze.py - Analisis estadistico de la Campania B (TFG OCC vs PCC)

Uso (desde la carpeta del proyecto):
    python analysis\\analyze.py                # analiza todas las campanias que existan en results_B
    python analysis\\analyze.py --campaign B1  # solo una

Requiere: pip install pandas numpy scipy matplotlib
Salida:  results_B\\analysis\\  (tablas .csv, figuras .png y resumen.md)
"""
import argparse, json, os, sys, warnings
import numpy as np
import pandas as pd
from scipy import stats as st

warnings.filterwarnings("ignore")
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RB = os.path.join(ROOT, "results_B")
OUT = os.path.join(RB, "analysis")
os.makedirs(OUT, exist_ok=True)
RNG = np.random.default_rng(20261016)
MD = []   # lineas del resumen


def md(s=""):
    MD.append(s)
    print(s)


def table_md(df, floatfmt=3):
    d = df.copy()
    for c in d.columns:
        if d[c].dtype.kind == "f":
            d[c] = d[c].map(lambda x: "" if pd.isna(x) else f"{x:.{floatfmt}f}")
    cols = list(d.columns)
    out = ["| " + " | ".join(map(str, cols)) + " |", "|" + "---|" * len(cols)]
    for _, r in d.iterrows():
        out.append("| " + " | ".join(str(r[c]) for c in cols) + " |")
    return "\n".join(out)


# ------------------------------------------------------------------ utilidades estadisticas
def ci_t(x, level=0.95):
    x = np.asarray(x, float)
    n = len(x)
    if n < 2:
        return np.nan, np.nan
    h = st.t.ppf((1 + level) / 2, n - 1) * x.std(ddof=1) / np.sqrt(n)
    return x.mean() - h, x.mean() + h


def hedges_g(a, b):
    a, b = np.asarray(a, float), np.asarray(b, float)
    n1, n2 = len(a), len(b)
    sp = np.sqrt(((n1 - 1) * a.var(ddof=1) + (n2 - 1) * b.var(ddof=1)) / (n1 + n2 - 2))
    if sp == 0:
        return np.nan
    return (1 - 3 / (4 * (n1 + n2) - 9)) * (a.mean() - b.mean()) / sp


def cliffs_delta(a, b):
    a, b = np.asarray(a), np.asarray(b)
    gt = sum((x > b).sum() for x in a)
    lt = sum((x < b).sum() for x in a)
    return (gt - lt) / (len(a) * len(b))


def boot_ratio_ci(a, b, n=10000):
    a, b = np.asarray(a, float), np.asarray(b, float)
    r = [RNG.choice(a, len(a)).mean() / RNG.choice(b, len(b)).mean() for _ in range(n)]
    return np.percentile(r, [2.5, 97.5])


def perm_p(a, b, n=20000):
    a, b = np.asarray(a, float), np.asarray(b, float)
    obs = abs(a.mean() - b.mean())
    allv = np.concatenate([a, b])
    cnt = 0
    for _ in range(n):
        RNG.shuffle(allv)
        if abs(allv[:len(a)].mean() - allv[len(a):].mean()) >= obs - 1e-12:
            cnt += 1
    return (cnt + 1) / (n + 1)


def holm(pvals):
    p = np.asarray(pvals, float)
    order = np.argsort(p)
    adj = np.empty_like(p)
    m = len(p)
    run = 0
    for rank, i in enumerate(order):
        run = max(run, (m - rank) * p[i])
        adj[i] = min(1, run)
    return adj


def clopper_pearson(k, n, level=0.95):
    a = 1 - level
    lo = 0.0 if k == 0 else st.beta.ppf(a / 2, k, n - k + 1)
    hi = 1.0 if k == n else st.beta.ppf(1 - a / 2, k + 1, n - k)
    return lo, hi


def dummies(df, cols):
    return pd.get_dummies(df[cols].astype(str), drop_first=True).astype(float)


def rss(y, X):
    X = np.column_stack([np.ones(len(y)), X]) if X is not None and X.shape[1] > 0 else np.ones((len(y), 1))
    beta, *_ = np.linalg.lstsq(X, y, rcond=None)
    r = y - X @ beta
    return float(r @ r), X.shape[1]


def anova2(df, y, a="strategy", b="load_label"):
    """ANOVA 2 factores, SS tipo II (valida tambien con datos desbalanceados)."""
    d = df[[a, b, y]].dropna().copy()
    yv = d[y].to_numpy(float)
    A = dummies(d, [a]).to_numpy()
    B = dummies(d, [b]).to_numpy()
    AB = np.column_stack([A[:, i] * B[:, j] for i in range(A.shape[1]) for j in range(B.shape[1])]) if A.shape[1] and B.shape[1] else np.zeros((len(d), 0))
    full = np.column_stack([A, B, AB])
    rss_full, p_full = rss(yv, full)
    dfe = len(d) - p_full
    mse = rss_full / dfe
    rows = {}
    rss_add, _ = rss(yv, np.column_stack([A, B]))
    rss_A, _ = rss(yv, A)
    rss_B, _ = rss(yv, B)
    for name, ss, dfn in [
        (a, rss_B - rss_add, A.shape[1]),
        (b, rss_A - rss_add, B.shape[1]),
        (f"{a}:{b}", rss_add - rss_full, AB.shape[1]),
    ]:
        F = (ss / dfn) / mse if dfn > 0 else np.nan
        rows[name] = dict(SS=ss, df=dfn, F=F, p=1 - st.f.cdf(F, dfn, dfe) if dfn > 0 else np.nan, eta_p2=ss / (ss + rss_full))
    res = pd.DataFrame(rows).T
    res.loc["Residual"] = dict(SS=rss_full, df=dfe, F=np.nan, p=np.nan, eta_p2=np.nan)
    # residuos para supuestos
    X = np.column_stack([np.ones(len(d)), full])
    beta, *_ = np.linalg.lstsq(X, yv, rcond=None)
    resid = yv - X @ beta
    sw = st.shapiro(resid)
    groups = [g[y].to_numpy(float) for _, g in d.groupby([a, b]) if len(g) > 1]
    lev = st.levene(*groups, center="median") if len(groups) > 1 else (np.nan, np.nan)
    return res, sw, lev


def cell_summary(df, y, by):
    g = df.groupby(by)[y]
    rows = []
    for k, s in g:
        lo, hi = ci_t(s.values)
        rows.append(dict(zip(by, k if isinstance(k, tuple) else (k,)), n=len(s), mean=s.mean(), sd=s.std(ddof=1),
                         median=s.median(), ci95_lo=lo, ci95_hi=hi))
    return pd.DataFrame(rows)


def read_runs(campaign):
    p = os.path.join(RB, campaign, "runs.csv")
    if not os.path.exists(p):
        return None
    d = pd.read_csv(p, encoding="utf-8-sig")
    for c in d.columns:
        if c not in ("run_id", "campaign", "strategy", "load_label", "app_errors_by_type", "audit_consistent", "run_valid"):
            d[c] = pd.to_numeric(d[c], errors="coerce")
    d["audit_consistent"] = d["audit_consistent"].astype(str).str.lower().eq("true")
    d["run_valid"] = d["run_valid"].astype(str).str.lower().eq("true")
    return d


def telemetry_window(row, campaign):
    p = os.path.join(RB, campaign, "raw", row["run_id"], "resources.csv")
    if not os.path.exists(p):
        return {}
    t = pd.read_csv(p)
    t0 = row["k6_start_epoch_ms"]
    lo = t0 + row["ramp_s"] * 1000 + 2000
    hi = t0 + (row["ramp_s"] + row["hold_s"]) * 1000
    w = t[(t.epoch_ms >= lo) & (t.epoch_ms <= hi)]
    if len(w) == 0:
        return {}
    return dict(tele_n=len(w), host_cpu_pct=w.host_cpu_pct.mean(), host_cpu_min=w.host_cpu_pct.min(),
                app_cpu_cores=w.app_cpu_pct_1core.mean() / 100, app_ws_mb=w.app_ws_mb.mean(),
                k6_cpu_cores=w.k6_cpu_pct_1core.mean() / 100, pg_cpu_cores=w.pg_cpu_pct_1core.mean() / 100,
                pg_mem_mb=w.pg_mem_mb.mean(), stalls=int((w.host_cpu_pct < 80).sum()))


def plot_box(d, y, by_x, hue, title, ylabel, fn):
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except Exception:
        return
    xs = sorted(d[by_x].unique(), key=lambda s: (len(str(s)), str(s)))
    hs = sorted(d[hue].unique())
    fig, ax = plt.subplots(figsize=(8, 4.5))
    w = 0.8 / len(hs)
    for i, h in enumerate(hs):
        data = [d[(d[by_x] == x) & (d[hue] == h)][y].values for x in xs]
        pos = [j + (i - (len(hs) - 1) / 2) * w for j in range(len(xs))]
        bp = ax.boxplot(data, positions=pos, widths=w * 0.9, patch_artist=True)
        for patch in bp["boxes"]:
            patch.set_facecolor(f"C{i}"); patch.set_alpha(0.6)
        ax.plot([], [], color=f"C{i}", label=str(h))
    ax.set_xticks(range(len(xs))); ax.set_xticklabels(xs)
    ax.set_title(title); ax.set_ylabel(ylabel); ax.legend(); ax.grid(alpha=0.3)
    fig.tight_layout(); fig.savefig(os.path.join(OUT, fn), dpi=150); plt.close(fig)


# ------------------------------------------------------------------ validez
def validity(d, name):
    md(f"### Validez de las corridas ({name})")
    bad = d[~d.run_valid]
    md(f"- Corridas registradas: **{len(d)}**; validas (k6 sin error y solicitudes totalmente clasificadas): **{int(d.run_valid.sum())}**.")
    if len(bad):
        md("- Corridas NO validas (excluir y repetir): " + ", ".join(bad.run_id))
    diff = d[d.k6_vs_app_success_diff.abs() > 0]
    md(f"- Corridas donde exitos de k6 y exitos confirmados por la app difieren: **{len(diff)}**" + (" (" + ", ".join(diff.run_id) + ")" if len(diff) else "."))
    e = d[d.k6_error > 0]
    md(f"- Corridas con errores HTTP (500 u otros): **{len(e)}**" + (" (" + ", ".join(e.run_id) + ")" if len(e) else "."))
    md("")


# ------------------------------------------------------------------ B1
def analyze_B1(d):
    md("## Campania B1 - Diseno factorial 2 x 3 (estrategia x carga)")
    validity(d, "B1")
    v = d[d.run_valid].copy()
    v["load_label"] = v["load_label"].astype(str)
    order = ["v100", "v500", "v1000"]
    v = v[v.load_label.isin(order)]
    # descriptivos
    for y, nm in [("lat_avg_ms", "latencia media (ms)"), ("lat_p95_ms", "latencia p95 (ms)"), ("throughput_rps", "throughput (req/s)")]:
        s = cell_summary(v, y, ["strategy", "load_label"])
        s["load_label"] = pd.Categorical(s["load_label"], order, ordered=True)
        s = s.sort_values(["strategy", "load_label"])
        s.to_csv(os.path.join(OUT, f"B1_desc_{y}.csv"), index=False)
        md(f"**{nm} por celda** (media, DE, IC95% t):"); md(table_md(s[["strategy", "load_label", "n", "mean", "sd", "median", "ci95_lo", "ci95_hi"]], 2)); md("")
    # conflictos OCC
    o = v[v.strategy == "occ"].copy()
    o["conflict_pct"] = 100 * o.k6_conflict / o.requests
    cs = cell_summary(o, "conflict_pct", ["load_label"])
    cs["load_label"] = pd.Categorical(cs["load_label"], order, ordered=True); cs = cs.sort_values("load_label")
    md("**Conflictos HTTP 409 en OCC (% de solicitudes):**"); md(table_md(cs[["load_label", "n", "mean", "sd", "ci95_lo", "ci95_hi"]], 2)); md("")
    # ANOVA
    v["ln_lat"] = np.log(v.lat_avg_ms)
    for y, nm in [("lat_avg_ms", "latencia media (escala original)"), ("ln_lat", "ln(latencia media) [analisis principal]"), ("throughput_rps", "throughput")]:
        res, sw, lev = anova2(v, y)
        res.to_csv(os.path.join(OUT, f"B1_anova_{y}.csv"))
        md(f"**ANOVA 2 vias - {nm}** (SS tipo II):"); md(table_md(res.reset_index().rename(columns={"index": "fuente"}), 4))
        md(f"Supuestos: Shapiro-Wilk residuos W={sw[0]:.3f}, p={sw[1]:.3f}; Levene (mediana) W={lev[0]:.2f}, p={lev[1]:.3f}."); md("")
    # comparaciones por carga
    rows = []
    for y in ["lat_avg_ms", "lat_p95_ms", "throughput_rps"]:
        ps = []
        tmp = []
        for ld in order:
            a = v[(v.strategy == "occ") & (v.load_label == ld)][y].values
            b = v[(v.strategy == "pcc") & (v.load_label == ld)][y].values
            if len(a) < 2 or len(b) < 2:
                continue
            w = st.ttest_ind(a, b, equal_var=False)
            mw = st.mannwhitneyu(a, b, alternative="two-sided")
            pp = perm_p(a, b)
            lo, hi = boot_ratio_ci(b, a)
            tmp.append(dict(metrica=y, carga=ld, n_occ=len(a), n_pcc=len(b), media_occ=a.mean(), media_pcc=b.mean(),
                            razon_pcc_sobre_occ=b.mean() / a.mean(), razon_ic95_lo=lo, razon_ic95_hi=hi,
                            welch_p=w.pvalue, mannwhitney_p=mw.pvalue, permutacion_p=pp,
                            hedges_g=hedges_g(a, b), cliffs_delta=cliffs_delta(a, b)))
            ps.append(pp)
        if tmp:
            adj = holm(ps)
            for r, pa in zip(tmp, adj):
                r["permutacion_p_holm"] = pa
            rows += tmp
    cmp_df = pd.DataFrame(rows)
    cmp_df.to_csv(os.path.join(OUT, "B1_comparaciones_por_carga.csv"), index=False)
    md("**OCC vs PCC por nivel de carga** (razon PCC/OCC con IC95% bootstrap; p de permutacion con correccion de Holm; g de Hedges; delta de Cliff; g y delta con signo OCC - PCC, es decir NEGATIVOS cuando OCC tiene menor latencia):")
    md(table_md(cmp_df.round(4), 4)); md("")
    # Ley de Little
    v["little_ms"] = v.vus / v.throughput_rps * 1000
    lt = v.groupby(["strategy", "load_label"])[["lat_avg_ms", "little_ms"]].mean().reset_index()
    lt["load_label"] = pd.Categorical(lt["load_label"], order, ordered=True); lt = lt.sort_values(["strategy", "load_label"])
    md("**Ley de Little (sistema cerrado): latencia esperada = VUs / throughput** (si coincide con la medida, el efecto de la carga es en gran parte mecanico):")
    md(table_md(lt, 1)); md("")
    plot_box(v, "lat_avg_ms", "load_label", "strategy", "B1 - Latencia media por corrida", "ms", "B1_latencia.png")
    plot_box(v, "throughput_rps", "load_label", "strategy", "B1 - Throughput por corrida", "req/s", "B1_throughput.png")
    # telemetria
    tele = []
    for _, r in v.iterrows():
        t = telemetry_window(r, "B1")
        if t:
            t.update(run_id=r.run_id, strategy=r.strategy, load_label=r.load_label); tele.append(t)
    if tele:
        T = pd.DataFrame(tele)
        T.to_csv(os.path.join(OUT, "B1_telemetria_por_corrida.csv"), index=False)
        s = T.groupby(["strategy", "load_label"])[["host_cpu_pct", "app_cpu_cores", "k6_cpu_cores", "pg_cpu_cores", "app_ws_mb", "pg_mem_mb", "stalls"]].mean().reset_index()
        md("**Telemetria en la ventana de medicion sostenida** (nucleos = % / 100; 'stalls' = muestras con CPU del host < 80%):")
        md(table_md(s, 2)); md("")
        try:
            if T.groupby(["strategy", "load_label"]).size().min() >= 2:
                res, sw, lev = anova2(T, "host_cpu_pct")
                md("ANOVA de CPU del host:"); md(table_md(res.reset_index().rename(columns={"index": "fuente"}), 4)); md("")
        except Exception as e:
            md(f"(ANOVA de CPU no calculable: {e})")


# ------------------------------------------------------------------ B2
def analyze_B2(d):
    md("## Campania B2 - Consistencia bajo alta contencion y stock escaso")
    validity(d, "B2")
    v = d[d.run_valid].copy()
    rows = []
    for s, g in v.groupby("strategy"):
        k = int(g.audit_consistent.sum()); n = len(g)
        lo, hi = clopper_pearson(k, n)
        rows.append(dict(estrategia=s, corridas=n, corridas_consistentes=k, prop_consistente=k / n, ic95_lo=lo, ic95_hi=hi,
                         unidades_perdidas_total=g.audit_lost_units.sum(), unidades_sobrevendidas_total=g.audit_oversold_units.sum(),
                         productos_stock_negativo=g.audit_products_negative.sum(),
                         ventas_ok_media=g.audit_total_success.mean(), oos_media=g.k6_oos.mean(),
                         conflictos409_media=g.k6_conflict.mean(), reintentos_media=g.app_retries.mean(),
                         errores500_total=g.k6_error.sum(), deadlocks_total=g.pg_deadlocks_delta.sum()))
    t = pd.DataFrame(rows)
    t.to_csv(os.path.join(OUT, "B2_consistencia.csv"), index=False)
    md("**Auditoria de consistencia por estrategia** (IC95% de Clopper-Pearson para la proporcion de corridas consistentes):")
    md(table_md(t, 3)); md("")
    md("Lectura: `none` es el CONTROL POSITIVO (sin control de concurrencia). Si la auditoria marca perdida de actualizaciones en `none` y cero en `occ`, `occretry` y `pcc`, el instrumento es capaz de detectar inconsistencias y la ausencia de ellas en OCC/PCC es evidencia valida. Con n corridas consistentes de n, el limite inferior del IC95% es ~(0.025)^(1/n); con 10 corridas es ~0.69.")
    md("")
    rows = []
    for y in ["lat_avg_ms", "lat_p95_ms", "throughput_rps"]:
        groups = {s: g[y].values for s, g in v.groupby("strategy") if len(g) > 1}
        if len(groups) < 2:
            continue
        kw = st.kruskal(*groups.values())
        rows.append(dict(metrica=y, kruskal_H=kw.statistic, kruskal_p=kw.pvalue))
        names = list(groups)
        pv, pairs = [], []
        for i in range(len(names)):
            for j in range(i + 1, len(names)):
                pv.append(st.mannwhitneyu(groups[names[i]], groups[names[j]], alternative="two-sided").pvalue)
                pairs.append((names[i], names[j]))
        adj = holm(pv)
        for (a, b), p0, p1 in zip(pairs, pv, adj):
            rows.append(dict(metrica=y, comparacion=f"{a} vs {b}", p_mannwhitney=p0, p_holm=p1,
                             media_a=groups[a].mean(), media_b=groups[b].mean()))
    pd.DataFrame(rows).to_csv(os.path.join(OUT, "B2_comparaciones.csv"), index=False)
    md("**Desempeno bajo alta contencion** (medias por estrategia):")
    md(table_md(v.groupby("strategy")[["lat_avg_ms", "lat_p95_ms", "throughput_rps"]].mean().reset_index(), 2)); md("")
    md("Comparaciones (Kruskal-Wallis y pares con Holm) en `B2_comparaciones.csv`."); md("")
    plot_box(v.assign(grupo="500 VUs"), "lat_avg_ms", "grupo", "strategy", "B2 - Latencia media (alta contencion)", "ms", "B2_latencia.png")


# ------------------------------------------------------------------ B3
def analyze_B3(d):
    md("## Campania B3 - Modelo abierto (llegadas constantes)")
    validity(d, "B3")
    v = d[d.run_valid].copy()
    # throughput_rps de k6 promedia tambien las rampas; la tasa efectiva en la meseta es requests / (rampa/2 + meseta + descenso/2)
    v["thr_eff"] = v.requests / (v.ramp_s / 2 + v.hold_s + v.down_s / 2)
    s = v.groupby(["strategy", "load_label"]).agg(n=("run_id", "count"), thr=("thr_eff", "mean"), lat=("lat_avg_ms", "mean"),
                                                   p95=("lat_p95_ms", "mean"), dropped=("k6_dropped_iter", "mean")).reset_index()
    s.to_csv(os.path.join(OUT, "B3_resumen.csv"), index=False)
    md(table_md(s, 2)); md("")
    rows = []
    for ld, g in v.groupby("load_label"):
        a = g[g.strategy == "occ"].lat_avg_ms.values; b = g[g.strategy == "pcc"].lat_avg_ms.values
        if len(a) > 1 and len(b) > 1:
            lo, hi = boot_ratio_ci(b, a)
            rows.append(dict(carga=ld, razon_pcc_occ=b.mean() / a.mean(), ic95_lo=lo, ic95_hi=hi, perm_p=perm_p(a, b), hedges_g=hedges_g(a, b)))
    if rows:
        md("**Latencia a igual tasa de llegada (PCC/OCC):**"); md(table_md(pd.DataFrame(rows), 4)); md("")
    md("Si `dropped` > 0 la estrategia no sostuvo la tasa ofrecida (saturacion): ese es el limite de capacidad de la estrategia en este entorno.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--campaign", choices=["B1", "B2", "B3"])
    args = ap.parse_args()
    md("# Resultados - Campania B")
    md("")
    md("Generado automaticamente por `analysis/analyze.py`. Todas las cifras provienen de `results_B/<campania>/runs.csv`.")
    md("")
    found = False
    for c, fn in [("B1", analyze_B1), ("B2", analyze_B2), ("B3", analyze_B3)]:
        if args.campaign and args.campaign != c:
            continue
        d = read_runs(c)
        if d is None or len(d) == 0:
            md(f"_(sin datos para {c})_"); md("")
            continue
        found = True
        fn(d)
    with open(os.path.join(OUT, "resumen.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(MD))
    if not found:
        print("No se encontraron datos. Ejecuta primero run_campaign.ps1.")
        sys.exit(1)
    print(f"\nListo. Resultados en: {OUT}")


if __name__ == "__main__":
    main()
