/*=============================================================================
  DS Tools — Spring 2026 Final Project
  Dataset : UCI Bank Marketing Dataset (bank.csv)
  Domain  : Customer Behavior / Direct Marketing
  Target  : Predict whether a client subscribes to a term deposit (y = yes/no)
=============================================================================*/

/*─────────────────────────────────────────────────────────────────────────────
  IMPORTANT NOTE ON CLASS IMBALANCE
  The target variable 'y' is heavily imbalanced:
    - "no"  = 4,000 rows (88.5%)
    - "yes" =   521 rows (11.5%)
  This means accuracy alone is a misleading metric. We focus on:
    - Sensitivity (recall for "yes") — catching subscribers
    - ROC-AUC score — overall discrimination ability
  A naive model that predicts "no" for everyone would score 88.5% accuracy
  but would be completely useless for the business.
─────────────────────────────────────────────────────────────────────────────*/

/*─────────────────────────────────────────────────────────────────────────────
  PHASE 1: IMPORT THE DATA
─────────────────────────────────────────────────────────────────────────────*/

proc import datafile="/home/u64507195/bank.csv"
    out=bank_data
    dbms=dlm
    replace;
    delimiter=';';
    getnames=yes;
run;

/* Quick sanity check — confirm 4521 rows, 17 columns */
proc contents data=bank_data varnum;
    title "Phase 1: Dataset Structure and Column Types";
run;

proc print data=bank_data (obs=10);
    title "Phase 1: First 10 Rows of Raw Data";
run;


/*─────────────────────────────────────────────────────────────────────────────
    PHASE 2: INVESTIGATE THE DATA (EDA — BEFORE CLEANING)
  Key finding: No true NULLs exist. Missingness is encoded as "unknown".
  We show PROC MEANS nmiss = 0, then separately count "unknown" strings.
─────────────────────────────────────────────────────────────────────────────*/

/* Statistical summary of all numeric columns */
proc means data=bank_data n nmiss mean std min max p25 p50 p75;
    var age balance duration campaign pdays previous;
    title "Phase 2: Numeric Column Summary (BEFORE Cleaning)";
run;

/* Frequency distributions of all categorical columns */
proc freq data=bank_data;
    tables job marital education default housing loan
           contact poutcome y / missing;
    title "Phase 2: Categorical Column Distributions (BEFORE Cleaning)";
run;

/* Count "unknown" strings per categorical column — our proxy for missing */
proc sql;
    select
        sum(job       = "unknown") as job_unknown,
        sum(education = "unknown") as education_unknown,
        sum(contact   = "unknown") as contact_unknown,
        sum(poutcome  = "unknown") as poutcome_unknown
    from bank_data;
    title "Phase 2: Count of 'unknown' Strings Per Column (Encoded Missingness)";
quit;


/── VISUALIZATIONS BEFORE CLEANING (Viz 1–4) ────────────────────────────────/

/* Viz 1: Age Distribution — understand who is being targeted */
title "Viz 1: Age Distribution of Bank Clients (Before Cleaning)";
proc sgplot data=bank_data;
    histogram age / fillattrs=(color=steelblue) transparency=0.2;
    density age / type=kernel lineattrs=(color=darkred thickness=2);
    xaxis label="Age of Client";
    yaxis label="Frequency";
run;

/* Viz 2: Box Plot — Call Duration vs Subscription Outcome
   NOTE: duration is a data-leakage variable (known only after the call ends).
   We include it for academic purposes but would exclude in production. */
title "Viz 2: Call Duration vs Subscription Outcome (Before Capping)";
proc sgplot data=bank_data;
    vbox duration / category=y fillattrs=(color=gold);
    xaxis label="Subscribed (y: yes/no)";
    yaxis label="Call Duration (seconds)";
run;

/* Viz 3: Job Title vs Subscription — which professions subscribe more? */
title "Viz 3: Job Title vs Subscription Status (Before Cleaning)";
proc sgplot data=bank_data;
    vbar job / group=y groupdisplay=cluster;
    xaxis label="Job Type" fitpolicy=rotate;
    yaxis label="Count of Clients";
    keylegend / title="Subscribed (y)";
run;

/* Viz 4: Scatter Plot — Age vs Balance (spot outliers) */
title "Viz 4: Age vs Yearly Balance — Outliers Visible (Before Cleaning)";
proc sgplot data=bank_data;
    scatter x=age y=balance / markerattrs=(symbol=circlefilled size=4px color=steelblue)
                               transparency=0.5;
    xaxis label="Age";
    yaxis label="Account Balance (Euro)";
run;


/*─────────────────────────────────────────────────────────────────────────────
  PHASE 3: CLEAN THE DATA
  Decisions made (each justified below):

  1. job = "unknown"      → DELETE  (only 38 rows, 0.8% — negligible loss)
  2. education = "unknown"→ DELETE  (187 rows, 4.1% — small, education is key feature)
  3. contact = "unknown"  → RECODE to "other" (29.3% — too many to delete;
                            "other" is a valid channel category)
  4. poutcome = "unknown" → KEEP AS-IS (82% of data — deleting would destroy
                            the dataset; "unknown" = no prior campaign, valid state)
  5. balance outliers     → CAP at 99th percentile (14,195 euro) — extreme
                            wealth outliers distort regression coefficients
  6. duration outliers    → CAP at 99th percentile (1,259 sec) — 5 extreme
                            calls (>2000s) likely system errors or edge cases
  7. campaign outliers    → CAP at 10 contacts (130 rows affected) — 50
                            contacts in one campaign is operationally unrealistic
  8. Negative balance     → KEEP — overdrafts are legitimate financial states
                            and may predict subscription behavior differently
─────────────────────────────────────────────────────────────────────────────*/

/* Step 1: Calculate the 99th percentile caps */
proc means data=bank_data noprint;
    var balance duration;
    output out=cap_stats
        p99(balance)  = balance_cap
        p99(duration) = duration_cap;
run;

data null;
    set cap_stats;
    call symputx('balance_cap',  put(balance_cap,  best12.));
    call symputx('duration_cap', put(duration_cap, best12.));
run;

%put Balance cap (P99)  = &balance_cap.;
%put Duration cap (P99) = &duration_cap.;

/* Step 2: Apply all cleaning rules */
data bank_cleaned;
    set bank_data;

    /* Rule 1-2: Remove rows with unknown job or education */
    if job       = "unknown" then delete;
    if education = "unknown" then delete;

    /* Rule 3: Recode unknown contact to "other" */
    if contact = "unknown" then contact = "other";

    /* Rule 4: poutcome "unknown" — intentionally KEPT as valid category */

    /* Rule 5: Cap extreme balance at P99 */
    if balance > &balance_cap. then balance = &balance_cap.;

    /* Rule 6: Cap extreme duration at P99 */
    if duration > &duration_cap. then duration = &duration_cap.;

    /* Rule 7: Cap campaign contacts at 10 */
    if campaign > 10 then campaign = 10;

run;

/* BEFORE vs AFTER snapshot */
proc means data=bank_data n mean std min max;
    var age balance duration campaign;
    title "Phase 3: BEFORE Cleaning — Numeric Summary";
run;

proc means data=bank_cleaned n mean std min max;
    var age balance duration campaign;
    title "Phase 3: AFTER Cleaning — Numeric Summary";
run;

/* Row count comparison */
proc sql;
    select "Before" as Stage, count(*) as Row_Count from bank_data
    union all
    select "After",           count(*) from bank_cleaned;
    title "Phase 3: Row Count Before vs After Cleaning";
quit;


/── VISUALIZATIONS AFTER CLEANING (Viz 5–6) ─────────────────────────────────/

/* Viz 5: Box Plot — Duration After Capping (before vs after comparison) */
title "Viz 5: Call Duration After Capping at P99 (After Cleaning)";
proc sgplot data=bank_cleaned;
    vbox duration / category=y fillattrs=(color=gold);
    xaxis label="Subscribed (y: yes/no)";
    yaxis label="Call Duration (seconds) — Capped at 1259s";
run;

/* Viz 6: Contact Method vs Subscription Rate (after recode) */
title "Viz 6: Contact Method vs Subscription Rate (After Cleaning)";
proc sgplot data=bank_cleaned;
    vbar contact / group=y stat=percent;
    xaxis label="Contact Method";
    yaxis label="Percentage (%)";
    keylegend / title="Subscribed (y)";
run;


/*─────────────────────────────────────────────────────────────────────────────
  PHASE 4: FEATURE ENGINEERING
  We create 7 new features, each justified by domain knowledge.
  Minimum requirement: 4 features after engineering — we deliver 7.
─────────────────────────────────────────────────────────────────────────────*/

data bank_features;
    set bank_cleaned;

    /*── Feature 1: age_group ─────────────────────────────────────────────────
      WHY: Age is continuous but subscription likelihood differs by life stage.
      Young adults (under 30) and elderly (over 60) show higher subscription
      rates in marketing literature. Bucketing captures non-linear age effects
      that a linear coefficient on raw age would miss.                        */
    length age_group $10.;
    if      age < 30 then age_group = "Young";
    else if age < 45 then age_group = "Middle";
    else if age < 60 then age_group = "Senior";
    else                  age_group = "Elderly";

    /*── Feature 2: balance_cat ───────────────────────────────────────────────
      WHY: Clients with higher balances may have different investment behavior.
      A categorical version captures threshold effects (e.g., wealthy clients
      behave very differently from those with near-zero balances).            */
    length balance_cat $10.;
    if      balance < 0    then balance_cat = "Negative";
    else if balance < 500  then balance_cat = "Low";
    else if balance < 5000 then balance_cat = "Medium";
    else                        balance_cat = "High";

    /*── Feature 3: is_repeat ─────────────────────────────────────────────────
      WHY: Clients contacted in previous campaigns already have brand awareness.
      Repeat contact is a strong behavioral signal — it means the bank believed
      this client was worth calling again.                                     */
    if previous > 0 then is_repeat = 1;
    else                 is_repeat = 0;

    /*── Feature 4: prev_success ──────────────────────────────────────────────
      WHY: If poutcome = "success", the client subscribed in the LAST campaign.
      Past behavior is the strongest predictor of future behavior. This binary
      flag isolates the highest-value signal in poutcome.                     */
    if poutcome = "success" then prev_success = 1;
    else                         prev_success = 0;

    /*── Feature 5: high_engagement ──────────────────────────────────────────
      WHY: A call lasting more than 5 minutes (300 seconds) signals the client
      was genuinely interested in the conversation. Short calls typically end
      in immediate rejection. This threshold captures engaged prospects.
      CAVEAT: duration is only known post-call (data leakage in production).  */
    if duration > 300 then high_engagement = 1;
    else                   high_engagement = 0;

    /*── Feature 6: season ────────────────────────────────────────────────────
      WHY: Bank marketing campaigns have strong seasonal patterns. Q2 (spring)
      and end-of-year (autumn/winter) are peak campaign periods. Month alone
      has 12 categories which creates sparse cells; season (4 groups) is more
      robust for a logistic model.                                            */
    length season $8.;
    if      month in ("dec" "jan" "feb") then season = "Winter";
    else if month in ("mar" "apr" "may") then season = "Spring";
    else if month in ("jun" "jul" "aug") then season = "Summer";
    else                                      season = "Autumn";

    /*── Feature 7: subscribed (binary target) ───────────────────────────────
      WHY: PROC LOGISTIC works best with a numeric 0/1 target. We recode the
      original "yes"/"no" string variable into a numeric binary for the model. */
    if y = "yes" then subscribed = 1;
    else              subscribed = 0;

run;

/* Verify engineered features */
proc freq data=bank_features;
    tables age_group balance_cat is_repeat prev_success
           high_engagement season subscribed / missing;
    title "Phase 4: Engineered Feature Distributions";
run;


/── VISUALIZATIONS FOR ENGINEERED FEATURES (Viz 7) ──────────────────────────/

/* Viz 7: Subscription Rate by Age Group and Season */
title "Viz 7: Subscription Rate by Age Group (Engineered Feature)";
proc sgplot data=bank_features;
    vbar age_group / group=y stat=percent groupdisplay=cluster;
    xaxis label="Age Group" order=("Young" "Middle" "Senior" "Elderly");
    yaxis label="Percentage (%)";
    keylegend / title="Subscribed (y)";
run;

/* Viz 7b: Previous Success vs Subscription Rate */
title "Viz 7b: Previous Campaign Success vs Current Subscription";
proc sgplot data=bank_features;
    vbar prev_success / group=y stat=percent groupdisplay=cluster;
    xaxis label="Previous Campaign Success (0=No, 1=Yes)";
    yaxis label="Percentage (%)";
    keylegend / title="Subscribed (y)";
run;


/*─────────────────────────────────────────────────────────────────────────────
  PHASE 5: BUILD THE MODEL
  Model: Binary Logistic Regression (PROC LOGISTIC)
  Target: subscribed (1 = yes, 0 = no)
  Split: 70% train / 30% test using PROC SURVEYSELECT
  Features: 4 engineered + 4 original numeric + categorical controls
─────────────────────────────────────────────────────────────────────────────*/

/* 70/30 Train-Test Split */
proc surveyselect data=bank_features
    out=split_data
    samprate=0.7
    outall
    seed=42;
run;

data bank_train bank_test;
    set split_data;
    if selected = 1 then output bank_train;
    else                 output bank_test;
run;

/* Verify split sizes */
proc sql;
    select "Train" as Split, count(*) as Rows,
           sum(subscribed) as Subscribers,
           round(mean(subscribed)*100, 0.1) as Pct_Yes
    from bank_train
    union all
    select "Test", count(*), sum(subscribed), round(mean(subscribed)*100, 0.1)
    from bank_test;
    title "Phase 5: Train/Test Split Summary";
quit;


/*── LOGISTIC REGRESSION MODEL ────────────────────────────────────────────────
  Notes on modeling choices:
  - EVENT='1' tells SAS we are predicting subscribed=1 (yes), not 0 (no)
  - DESCENDING ensures probabilities are for the rare/positive class
  - STEPWISE selection removes features that do not contribute significantly
  - slentry=0.05 / slstay=0.05 are standard significance thresholds
  - CLASS statement handles categorical variables with reference coding
  - PLOTS=ROC generates the ROC curve (Viz 8)
  - OUTROC= saves AUC and ROC curve data points for reporting
─────────────────────────────────────────────────────────────────────────────*/

proc logistic data=bank_train descending
    plots(only)=(roc oddsratio);
    class age_group (ref="Middle")
          balance_cat (ref="Low")
          season (ref="Spring")
          marital (ref="married")
          / param=ref;
    model subscribed(event='1') =
        /* Engineered features */
        is_repeat prev_success high_engagement
        /* Original numeric features */
        duration campaign age balance
        /* Original categorical features */
        age_group balance_cat season marital
        / selection=stepwise
          slentry=0.05
          slstay=0.05
          ctable                /* confusion matrix at 0.5 threshold  */
          pprob=0.5             /* classification cutoff               */
          lackfit;              /* Hosmer-Lemeshow goodness-of-fit     */
    output out=train_pred
        predicted=pred_prob
        xbeta=log_odds;
    ods output OddsRatios=or_table;   /* save for Viz 8 */
    ods output Association=auc_table; /* save AUC value */
    title "Phase 5: Logistic Regression Model — Bank Term Deposit Subscription";
run;

/* Score the test set */
proc logistic data=bank_train descending noprint;
    class age_group (ref="Middle")
          balance_cat (ref="Low")
          season (ref="Spring")
          marital (ref="married")
          / param=ref;
    model subscribed(event='1') =
        is_repeat prev_success high_engagement
        duration campaign age balance
        age_group balance_cat season marital;
    score data=bank_test out=test_pred_raw;
run;

/* Add actual labels to test predictions */
data test_pred;
    merge bank_test (keep=subscribed)
          test_pred_raw;
    predicted_class = (P_1 >= 0.5);
run;


/*─────────────────────────────────────────────────────────────────────────────
  PHASE 6: EVALUATE AND EXPLAIN THE MODEL
─────────────────────────────────────────────────────────────────────────────*/

/* Confusion Matrix on Test Set */
proc freq data=test_pred;
    tables subscribed * predicted_class /
           norow nocol nopercent
           agree;
    title "Phase 6: Confusion Matrix on Test Set (Threshold = 0.50)";
run;

/* Accuracy, Sensitivity, Specificity manually */
proc sql;
    select
        count(*)                                           as Total,
        sum(subscribed = predicted_class)                  as Correct,
        round(mean(subscribed = predicted_class)*100, 0.1) as Accuracy_Pct,
        /* Sensitivity = TP / (TP + FN) */
        round(
            sum(subscribed=1 and predicted_class=1) /
            sum(subscribed=1) * 100, 0.1)                  as Sensitivity_Pct,
        /* Specificity = TN / (TN + FP) */
        round(
            sum(subscribed=0 and predicted_class=0) /
            sum(subscribed=0) * 100, 0.1)                  as Specificity_Pct
    from test_pred;
    title "Phase 6: Model Performance Metrics on Test Set";
quit;

/* Display AUC from training model */
proc print data=auc_table noobs;
    title "Phase 6: Model AUC (Area Under ROC Curve) — Training Set";
run;


/*── VIZ 8: FEATURE IMPORTANCE — ODDS RATIO PLOT ─────────────────────────────
  Odds Ratio interpretation:
  - OR > 1 means this feature INCREASES probability of subscription
  - OR < 1 means this feature DECREASES probability of subscription
  - Wider confidence interval = less certain effect
─────────────────────────────────────────────────────────────────────────────*/
title "Viz 8: Feature Importance — Odds Ratios with 95% Confidence Intervals";
proc sgplot data=or_table;
    dot Effect /
        response=OddsRatioEst
        limitlower=LowerCL
        limitupper=UpperCL
        markerattrs=(symbol=CircleFilled size=10px color=steelblue)
        lineattrs=(color=steelblue);
    refline 1 / axis=x
                lineattrs=(pattern=shortdash color=red thickness=2);
    xaxis label="Odds Ratio (values > 1 increase subscription probability)"
          min=0;
    yaxis label="Feature";
run;
title;


/*── VIZ 9: PREDICTED PROBABILITY DISTRIBUTION (Bonus) ───────────────────────
  Shows how well the model separates subscribers from non-subscribers.
  A good model shows two distinct humps — one near 0 and one near 1.         */
title "Viz 9 (Bonus): Predicted Probability Distribution by Actual Outcome";
proc sgplot data=test_pred;
    histogram P_1 / group=subscribed transparency=0.4
                    fillattrs=(color=steelblue)
                    nbins=30;
    density P_1 / group=subscribed type=kernel;
    xaxis label="Predicted Probability of Subscription";
    yaxis label="Count";
    keylegend / title="Actual Subscribed (0=No, 1=Yes)";
run;
title;


/── VIZ 10: MARITAL STATUS PIE CHART ────────────────────────────────────────/
title "Viz 10: Distribution of Marital Status in Cleaned Dataset";
proc gchart data=bank_features;
    pie marital / discrete
                  value=inside
                  percent=outside
                  slice=arrow;
run;
quit;


/── VIZ 11: CORRELATION HEATMAP ─────────────────────────────────────────────/
proc corr data=bank_features noprint outp=corr_out;
    var age balance duration campaign pdays previous;
run;

data corr_plot;
    set corr_out;
    where TYPE = 'CORR';
    array vars age balance duration campaign pdays previous;
    do i = 1 to dim(vars);
        VarName2 = vname(vars[i]);
        Correlation = vars[i];
        output;
    end;
    rename NAME = VarName1;
    keep NAME VarName2 Correlation;
run;

title "Viz 11: Correlation Heatmap — Numeric Features (After Cleaning)";
proc sgplot data=corr_plot;
    heatmapparm x=VarName1 y=VarName2 colorvar=Correlation /
                colormodel=(blue white red) x2axis;
    gradlegend / title="Correlation";
run;
title;


/*─────────────────────────────────────────────────────────────────────────────
  PHASE 7: MAKE IT USEFUL — GENERATE PREDICTIONS FOR NEW CLIENTS
  Export the scored test set with predicted probabilities for reporting.
─────────────────────────────────────────────────────────────────────────────*/

/* Add readable risk labels to predictions */
data final_predictions;
    set test_pred;
    length risk_label $12.;
    if      P_1 >= 0.70 then risk_label = "High";
    else if P_1 >= 0.40 then risk_label = "Medium";
    else                     risk_label = "Low";
    keep subscribed P_1 predicted_class risk_label;
run;

/* Summary of predictions by risk tier */
proc freq data=final_predictions;
    tables risk_label * subscribed / norow nocol nopercent;
    title "Phase 7: Predicted Risk Tiers vs Actual Subscription";
run;

/* Export final predictions to CSV */
proc export data=final_predictions
    outfile="/home/u64507195/bank_predictions.csv"
    dbms=csv
    replace;
run;

proc means data=final_predictions;
    class risk_label;
    var P_1 subscribed;
    title "Phase 7: Average Subscription Rate per Risk Tier";
run;



