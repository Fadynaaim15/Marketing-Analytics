# Marketing-Analytics
A production-grade SAS programming workflow designed to automate data ingestion, execute comprehensive exploratory data analysis (EDA), perform robust statistical cleaning, and train a predictive model targeting customer subscription behavior.
# Bank Marketing Analytics: End-to-End SAS Data Pipeline & Predictive Modeling

A production-grade SAS programming workflow designed to automate data ingestion, execute comprehensive exploratory data analysis (EDA), perform robust statistical cleaning, and train a predictive model targeting customer subscription behavior.

## 🎯 Project Objective
[cite_start]The goal is to predict whether a client will subscribe to a term deposit (`y = yes/no`) based on direct marketing campaign data. 

### ⚠️ Core Challenge: Class Imbalance
The target variable is heavily skewed:
* [cite_start]**"No" (Non-subscribers):** 88.5% (4,000 rows) 
* [cite_start]**"Yes" (Subscribers):** 11.5% (521 rows) 

[cite_start]Because accuracy is misleading in imbalanced contexts, this pipeline intentionally optimizes for **Sensitivity (Recall for "yes")** and **ROC-AUC Score** to deliver real business value[cite: 2].

---

## 🚀 Data Engineering & Pipeline Architecture

### 1. Programmatic Data Ingestion (Phase 1)
* [cite_start]Dynamically imports delimiter-separated files using `PROC IMPORT` with strict character encoding configurations[cite: 3, 4].
* [cite_start]Implements structural health checks using `PROC CONTENTS` and automated row/column validation[cite: 4, 5].

### 2. Missingness Profile & Data Cleaning (Phase 2 & 3)
* [cite_start]**Missing Value Resolution:** Investigated data profile where missingness was masked as `"unknown"` strings[cite: 8]. [cite_start]Programmatically removed negligible rows (`job` and `education`) [cite: 34, 35] [cite_start]while recoding structural categories (`contact` turned to `"other"`) to preserve data volume[cite: 35, 36].
* [cite_start]**Statistical Outlier Capping:** Dynamically calculated the 99th percentile ($P_{99}$) thresholds via `PROC MEANS`[cite: 30]. [cite_start]Automatically capped extreme variables (`balance` capped at €14,195, `duration` capped at 1,259s, and `campaign` capped at 10 contacts) using SAS Macro variables to prevent regression coefficient distortion[cite: 28, 29, 31].

### 3. Feature Engineering (Phase 4)
[cite_start]Exceeded the baseline specifications by engineering **7 custom domain-driven features** within a single data step[cite: 49]:
* [cite_start]`age_group`: Captures non-linear life-stage effects (Young, Middle, Senior, Elderly)[cite: 52, 53].
* [cite_start]`balance_cat`: Segmented wealth tiers to extract threshold effects[cite: 57, 58].
* [cite_start]`is_repeat`: Binary indicator flags brand awareness from past exposures[cite: 61, 62].
* [cite_start]`prev_success`: Isolates the highest-value conversion signal from historical campaigns[cite: 66, 67].
* [cite_start]`high_engagement`: Captures calls exceeding 5 minutes, mapping true prospect interest[cite: 69].
* [cite_start]`season`: Collapses 12 distinct months into robust quarterly blocks to reduce cell sparsity[cite: 74, 76, 77].
* [cite_start]`subscribed`: Numeric binary target ($0/1$) optimization for logistic modeling[cite: 82, 83].

---

## 🧠 Predictive Modeling & Evaluation (Phase 5 & 6)

* [cite_start]**Data Partitioning:** Implemented a reproducible 70% Train / 30% Test split using `PROC SURVEYSELECT` (Seed: 42)[cite: 91, 92].
* [cite_start]**Statistical Modeling:** Deployed a Binary Logistic Regression model (`PROC LOGISTIC`) utilizing **Stepwise Selection** with standard significance thresholds ($slentry=0.05 / slstay=0.05$)[cite: 95, 97].
* [cite_start]**Advanced Diagnostics:** Integrated Hosmer-Lemeshow goodness-of-fit testing (`lackfit`) and confusion matrix generation (`ctable`)[cite: 98, 99].
* [cite_start]**Operational Risk Tiering:** Scored testing partitions, mapping mathematical probabilities (`P_1`) into actionable business labels: High ($\ge 70\%$), Medium ($\ge 40\%$), and Low Risk[cite: 105, 132, 133].

---

## 🛠️ SAS Procedures Utilized
* [cite_start]**Data Exploration:** `PROC CONTENTS` [cite: 4][cite_start], `PROC PRINT` [cite: 6][cite_start], `PROC MEANS` [cite: 9][cite_start], `PROC FREQ` [cite: 11]
* [cite_start]**Statistical Modeling:** `PROC LOGISTIC` [cite: 95][cite_start], `PROC CORR` [cite: 125]
* [cite_start]**Data Processing & Sampling:** `PROC IMPORT` [cite: 3][cite_start], `PROC SQL` [cite: 13][cite_start], `PROC SURVEYSELECT` [cite: 91][cite_start], `PROC EXPORT` [cite: 136]
* [cite_start]**Advanced Visualizations:** `PROC SGPLOT` (Histograms, Box plots, Scatter plots, Heatmaps) [cite: 17, 20, 22, 25, 128] [cite_start]& `PROC GCHART` [cite: 123]
