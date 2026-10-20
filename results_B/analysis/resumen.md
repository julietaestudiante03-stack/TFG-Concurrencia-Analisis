# Resultados - Campania B

Generado automaticamente por `analysis/analyze.py`. Todas las cifras provienen de `results_B/<campania>/runs.csv`.

## Campania B1 - Diseno factorial 2 x 3 (estrategia x carga)
### Validez de las corridas (B1)
- Corridas registradas: **60**; validas (k6 sin error y solicitudes totalmente clasificadas): **60**.
- Corridas donde exitos de k6 y exitos confirmados por la app difieren: **0**.
- Corridas con errores HTTP (500 u otros): **0**.

**latencia media (ms) por celda** (media, DE, IC95% t):
| strategy | load_label | n | mean | sd | median | ci95_lo | ci95_hi |
|---|---|---|---|---|---|---|---|
| occ | v100 | 10 | 18.97 | 0.49 | 19.16 | 18.62 | 19.32 |
| occ | v500 | 10 | 82.44 | 1.14 | 82.83 | 81.62 | 83.26 |
| occ | v1000 | 10 | 164.77 | 1.08 | 164.67 | 164.00 | 165.54 |
| pcc | v100 | 10 | 19.05 | 0.41 | 19.10 | 18.76 | 19.34 |
| pcc | v500 | 10 | 82.95 | 1.15 | 82.94 | 82.13 | 83.78 |
| pcc | v1000 | 10 | 165.50 | 1.59 | 165.78 | 164.36 | 166.64 |

**latencia p95 (ms) por celda** (media, DE, IC95% t):
| strategy | load_label | n | mean | sd | median | ci95_lo | ci95_hi |
|---|---|---|---|---|---|---|---|
| occ | v100 | 10 | 27.30 | 0.46 | 27.49 | 26.96 | 27.63 |
| occ | v500 | 10 | 111.97 | 1.17 | 112.26 | 111.14 | 112.81 |
| occ | v1000 | 10 | 208.71 | 0.88 | 208.70 | 208.08 | 209.35 |
| pcc | v100 | 10 | 27.72 | 0.21 | 27.72 | 27.57 | 27.87 |
| pcc | v500 | 10 | 113.52 | 1.50 | 113.58 | 112.44 | 114.59 |
| pcc | v1000 | 10 | 210.21 | 1.64 | 210.26 | 209.03 | 211.38 |

**throughput (req/s) por celda** (media, DE, IC95% t):
| strategy | load_label | n | mean | sd | median | ci95_lo | ci95_hi |
|---|---|---|---|---|---|---|---|
| occ | v100 | 10 | 4692.66 | 120.77 | 4644.33 | 4606.27 | 4779.05 |
| occ | v500 | 10 | 5447.31 | 75.51 | 5421.30 | 5393.29 | 5501.32 |
| occ | v1000 | 10 | 5458.84 | 35.72 | 5462.07 | 5433.29 | 5484.39 |
| pcc | v100 | 10 | 4672.93 | 100.56 | 4658.22 | 4601.00 | 4744.86 |
| pcc | v500 | 10 | 5413.90 | 74.78 | 5414.20 | 5360.41 | 5467.40 |
| pcc | v1000 | 10 | 5435.07 | 52.47 | 5425.58 | 5397.54 | 5472.60 |

**Conflictos HTTP 409 en OCC (% de solicitudes):**
| load_label | n | mean | sd | ci95_lo | ci95_hi |
|---|---|---|---|---|---|
| v100 | 10 | 1.98 | 0.03 | 1.96 | 2.00 |
| v500 | 10 | 4.25 | 0.04 | 4.23 | 4.28 |
| v1000 | 10 | 4.30 | 0.03 | 4.28 | 4.33 |

**ANOVA 2 vias - latencia media (escala original)** (SS tipo II):
| fuente | SS | df | F | p | eta_p2 |
|---|---|---|---|---|---|
| strategy | 2.9228 | 1.0000 | 2.6023 | 0.1125 | 0.0460 |
| load_label | 214697.7106 | 2.0000 | 95575.2191 | 0.0000 | 0.9997 |
| strategy:load_label | 1.1090 | 2.0000 | 0.4937 | 0.6131 | 0.0180 |
| Residual | 60.6521 | 54.0000 |  |  |  |
Supuestos: Shapiro-Wilk residuos W=0.992, p=0.956; Levene (mediana) W=3.34, p=0.011.

**ANOVA 2 vias - ln(latencia media) [analisis principal]** (SS tipo II):
| fuente | SS | df | F | p | eta_p2 |
|---|---|---|---|---|---|
| strategy | 0.0004 | 1.0000 | 1.3357 | 0.2529 | 0.0241 |
| load_label | 48.7625 | 2.0000 | 88556.7723 | 0.0000 | 0.9997 |
| strategy:load_label | 0.0000 | 2.0000 | 0.0207 | 0.9795 | 0.0008 |
| Residual | 0.0149 | 54.0000 |  |  |  |
Supuestos: Shapiro-Wilk residuos W=0.985, p=0.665; Levene (mediana) W=2.82, p=0.025.

**ANOVA 2 vias - throughput** (SS tipo II):
| fuente | SS | df | F | p | eta_p2 |
|---|---|---|---|---|---|
| strategy | 9855.7092 | 1.0000 | 1.4776 | 0.2294 | 0.0266 |
| load_label | 7622866.7333 | 2.0000 | 571.4404 | 0.0000 | 0.9549 |
| strategy:load_label | 493.4772 | 2.0000 | 0.0370 | 0.9637 | 0.0014 |
| Residual | 360173.0028 | 54.0000 |  |  |  |
Supuestos: Shapiro-Wilk residuos W=0.985, p=0.658; Levene (mediana) W=2.18, p=0.070.

**OCC vs PCC por nivel de carga** (razon PCC/OCC con IC95% bootstrap; p de permutacion con correccion de Holm; g de Hedges; delta de Cliff; g y delta con signo OCC - PCC, es decir NEGATIVOS cuando OCC tiene menor latencia):
| metrica | carga | n_occ | n_pcc | media_occ | media_pcc | razon_pcc_sobre_occ | razon_ic95_lo | razon_ic95_hi | welch_p | mannwhitney_p | permutacion_p | hedges_g | cliffs_delta | permutacion_p_holm |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| lat_avg_ms | v100 | 10 | 10 | 18.9715 | 19.0506 | 1.0042 | 0.9847 | 1.0244 | 0.6997 | 0.9097 | 0.6941 | -0.1680 | -0.0400 | 0.7279 |
| lat_avg_ms | v500 | 10 | 10 | 82.4410 | 82.9521 | 1.0062 | 0.9949 | 1.0182 | 0.3324 | 0.6232 | 0.3377 | -0.4267 | -0.1400 | 0.7279 |
| lat_avg_ms | v1000 | 10 | 10 | 164.7690 | 165.5031 | 1.0045 | 0.9974 | 1.0111 | 0.2452 | 0.3075 | 0.2426 | -0.5169 | -0.2800 | 0.7279 |
| lat_p95_ms | v100 | 10 | 10 | 27.2968 | 27.7205 | 1.0155 | 1.0053 | 1.0272 | 0.0214 | 0.0113 | 0.0098 | -1.1251 | -0.6800 | 0.0295 |
| lat_p95_ms | v500 | 10 | 10 | 111.9712 | 113.5166 | 1.0138 | 1.0039 | 1.0237 | 0.0199 | 0.0073 | 0.0180 | -1.1007 | -0.7200 | 0.0361 |
| lat_p95_ms | v1000 | 10 | 10 | 208.7146 | 210.2068 | 1.0071 | 1.0018 | 1.0122 | 0.0241 | 0.0539 | 0.0223 | -1.0849 | -0.5200 | 0.0361 |
| throughput_rps | v100 | 10 | 10 | 4692.6594 | 4672.9308 | 0.9958 | 0.9766 | 1.0151 | 0.6962 | 0.9097 | 0.6965 | 0.1700 | 0.0400 | 0.7432 |
| throughput_rps | v500 | 10 | 10 | 5447.3057 | 5413.9038 | 0.9939 | 0.9823 | 1.0050 | 0.3334 | 0.6232 | 0.3316 | 0.4257 | 0.1400 | 0.7432 |
| throughput_rps | v1000 | 10 | 10 | 5458.8411 | 5435.0728 | 0.9956 | 0.9890 | 1.0028 | 0.2538 | 0.3075 | 0.2477 | 0.5072 | 0.2800 | 0.7432 |

**Ley de Little (sistema cerrado): latencia esperada = VUs / throughput** (si coincide con la medida, el efecto de la carga es en gran parte mecanico):
| strategy | load_label | lat_avg_ms | little_ms |
|---|---|---|---|
| occ | v100 | 19.0 | 21.3 |
| occ | v500 | 82.4 | 91.8 |
| occ | v1000 | 164.8 | 183.2 |
| pcc | v100 | 19.1 | 21.4 |
| pcc | v500 | 83.0 | 92.4 |
| pcc | v1000 | 165.5 | 184.0 |

**Telemetria en la ventana de medicion sostenida** (nucleos = % / 100; 'stalls' = muestras con CPU del host < 80%):
| strategy | load_label | host_cpu_pct | app_cpu_cores | k6_cpu_cores | pg_cpu_cores | app_ws_mb | pg_mem_mb | stalls |
|---|---|---|---|---|---|---|---|---|
| occ | v100 | 97.19 | 2.25 | 1.44 | 3.83 | 814.70 | 361.00 | 0.10 |
| occ | v1000 | 97.40 | 2.30 | 1.66 | 4.43 | 854.73 | 386.97 | 0.20 |
| occ | v500 | 97.53 | 2.33 | 1.63 | 4.45 | 844.37 | 386.69 | 0.20 |
| pcc | v100 | 96.87 | 2.22 | 1.47 | 3.95 | 812.83 | 361.60 | 0.20 |
| pcc | v1000 | 97.79 | 2.30 | 1.61 | 4.50 | 854.79 | 388.38 | 0.10 |
| pcc | v500 | 97.88 | 2.32 | 1.65 | 4.53 | 845.92 | 387.74 | 0.10 |

ANOVA de CPU del host:
| fuente | SS | df | F | p | eta_p2 |
|---|---|---|---|---|---|
| strategy | 0.2933 | 1.0000 | 0.2561 | 0.6149 | 0.0047 |
| load_label | 5.2460 | 2.0000 | 2.2903 | 0.1110 | 0.0782 |
| strategy:load_label | 1.6031 | 2.0000 | 0.6999 | 0.5011 | 0.0253 |
| Residual | 61.8448 | 54.0000 |  |  |  |

## Campania B2 - Consistencia bajo alta contencion y stock escaso
### Validez de las corridas (B2)
- Corridas registradas: **40**; validas (k6 sin error y solicitudes totalmente clasificadas): **40**.
- Corridas donde exitos de k6 y exitos confirmados por la app difieren: **0**.
- Corridas con errores HTTP (500 u otros): **40** (B2_pcc_v500_1, B2_occ_v500_1, B2_occretry_v500_1, B2_none_v500_1, B2_none_v500_2, B2_occ_v500_2, B2_pcc_v500_2, B2_occretry_v500_2, B2_pcc_v500_3, B2_occretry_v500_3, B2_occ_v500_3, B2_none_v500_3, B2_none_v500_4, B2_pcc_v500_4, B2_occ_v500_4, B2_occretry_v500_4, B2_pcc_v500_5, B2_occ_v500_5, B2_occretry_v500_5, B2_none_v500_5, B2_occ_v500_6, B2_occretry_v500_6, B2_none_v500_6, B2_pcc_v500_6, B2_pcc_v500_7, B2_occretry_v500_7, B2_none_v500_7, B2_occ_v500_7, B2_none_v500_8, B2_occ_v500_8, B2_occretry_v500_8, B2_pcc_v500_8, B2_none_v500_9, B2_occretry_v500_9, B2_pcc_v500_9, B2_occ_v500_9, B2_none_v500_10, B2_occretry_v500_10, B2_occ_v500_10, B2_pcc_v500_10)

**Auditoria de consistencia por estrategia** (IC95% de Clopper-Pearson para la proporcion de corridas consistentes):
| estrategia | corridas | corridas_consistentes | prop_consistente | ic95_lo | ic95_hi | unidades_perdidas_total | unidades_sobrevendidas_total | productos_stock_negativo | ventas_ok_media | oos_media | conflictos409_media | reintentos_media | errores500_total | deadlocks_total |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| none | 10 | 0 | 0.000 | 0.000 | 0.308 | 834369 | 833518 | 0 | 219015.600 | 59412.800 | 0.000 | 0.000 | 180806 | 0 |
| occ | 10 | 10 | 1.000 | 0.692 | 1.000 | 0 | 0 | 0 | 130721.600 | 40633.800 | 82684.200 | 0.000 | 99751 | 0 |
| occretry | 10 | 10 | 1.000 | 0.692 | 1.000 | 0 | 0 | 0 | 114824.400 | 50671.400 | 8715.900 | 61308.800 | 122525 | 0 |
| pcc | 10 | 10 | 1.000 | 0.692 | 1.000 | 0 | 0 | 0 | 120305.600 | 81183.500 | 0.000 | 0.000 | 212531 | 0 |

Lectura: `none` es el CONTROL POSITIVO (sin control de concurrencia). Si la auditoria marca perdida de actualizaciones en `none` y cero en `occ`, `occretry` y `pcc`, el instrumento es capaz de detectar inconsistencias y la ausencia de ellas en OCC/PCC es evidencia valida. Con n corridas consistentes de n, el limite inferior del IC95% es ~(0.025)^(1/n); con 10 corridas es ~0.69.

**Desempeno bajo alta contencion** (medias por estrategia):
| strategy | lat_avg_ms | lat_p95_ms | throughput_rps |
|---|---|---|---|
| none | 59.72 | 110.92 | 4941.66 |
| occ | 76.96 | 141.01 | 4400.12 |
| occretry | 100.95 | 227.49 | 3107.60 |
| pcc | 59.14 | 131.06 | 3712.23 |

Comparaciones (Kruskal-Wallis y pares con Holm) en `B2_comparaciones.csv`.

## Campania B3 - Modelo abierto (llegadas constantes)
### Validez de las corridas (B3)
- Corridas registradas: **24**; validas (k6 sin error y solicitudes totalmente clasificadas): **24**.
- Corridas donde exitos de k6 y exitos confirmados por la app difieren: **0**.
- Corridas con errores HTTP (500 u otros): **0**.

| strategy | load_label | n | thr | lat | p95 | dropped |
|---|---|---|---|---|---|---|
| occ | r2000 | 6 | 2000.06 | 5.26 | 7.21 | 0.00 |
| occ | r4000 | 6 | 4000.06 | 11.77 | 21.31 | 0.00 |
| pcc | r2000 | 6 | 1998.89 | 6.67 | 10.06 | 79.00 |
| pcc | r4000 | 6 | 3998.11 | 12.28 | 22.65 | 131.67 |

**Latencia a igual tasa de llegada (PCC/OCC):**
| carga | razon_pcc_occ | ic95_lo | ic95_hi | perm_p | hedges_g |
|---|---|---|---|---|---|
| r2000 | 1.2670 | 1.0480 | 1.5295 | 0.0660 | -1.0405 |
| r4000 | 1.0433 | 0.9520 | 1.1377 | 0.4022 | -0.4549 |

Si `dropped` > 0 la estrategia no sostuvo la tasa ofrecida (saturacion): ese es el limite de capacidad de la estrategia en este entorno.