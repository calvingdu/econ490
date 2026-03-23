// Emigration Rate with Solow Model
// Data: IAB Brain Drain Dataset + Penn World Tables 11.0 + World Bank dataset
// IAB coverage: 1980, 1985, 1990, 1995, 2000, 2005, 2010
// 
// CITATIONS:
// IAB Brain Drain Dataset:
//   Brücker H., Capuano, S. and Marfouk, A. (2013). Education, gender and
//   international migration: insights from a panel-dataset 1980-2010, mimeo.
//   URL: https://iab.de/en/daten/iab-brain-drain/
//
// Penn World Tables 11.0:
//   Feenstra, R. C., Inklaar, R., & Timmer, M. P. (2015). The Next Generation
//   of the Penn World Table. American Economic Review, 105(10), 3150-3182.
//   URL: www.ggdc.net/pwt
//
// World Bank Country Classifications:
//   World Bank (2025). World Bank Country and Lending Groups.
//   URL: https://datahelpdesk.worldbank.org/knowledgebase/articles/906519-world-bank-country-and-lending-groups

// 0. File setup 
cd "/Users/calvindu/School/2025W2/ECON490/project/iab/gender_specific"
capture mkdir "1.made_data"
capture mkdir "2.output"

capture log close
log using "2.output/IABEmigrationAll.log", text replace


// 1. PREPARE DATA
// 1.1 IAB DATA
// Reshape to wide: one row per country-year with 3 emig rate columns (total, male, female)
// Emigration is defined as population emigrated / total population
// so for example tot_ratemale = male emigrants / male population which is why they're unrelated

use "0.source_data/iabbd_8010_v1_emigration.dta", clear
keep ccode_origin year gender tot_rate
rename ccode_origin countrycode

gen gtype = ""
replace gtype = "combined" if gender == "Male and Female"
replace gtype = "male" if gender == "Male"
replace gtype = "female" if gender == "Female"
drop gender

reshape wide tot_rate, i(countrycode year) j(gtype) string

rename tot_ratecombined emig_combined
rename tot_ratemale     emig_male
rename tot_ratefemale   emig_female

// Convert proportions to percentages
replace emig_combined = emig_combined * 100
replace emig_male     = emig_male * 100
replace emig_female   = emig_female * 100

label var emig_combined  "Emigration rate, combined (% of population)"
label var emig_male 	 "Emigration rate, male (% of population)"
label var emig_female	 "Emigration rate, female (% of population)"

save "1.made_data/iab_clean_wide.dta", replace

// 1.2. PWT Data
use "0.source_data/pwt110.dta", clear

global solow_variables "rgdpe pop csh_i hc"
keep ${solow_variables} year countrycode

// Assign PWT years to nearest IAB 5-year period
generate period = .
replace period = 1980 if year >= 1978 & year <= 1982
replace period = 1985 if year >= 1983 & year <= 1987
replace period = 1990 if year >= 1988 & year <= 1992
replace period = 1995 if year >= 1993 & year <= 1997
replace period = 2000 if year >= 1998 & year <= 2002
replace period = 2005 if year >= 2003 & year <= 2007
replace period = 2010 if year >= 2008 & year <= 2012
drop if missing(period)

// Collapse to 5-year period averages
collapse (mean) csh_i rgdpe pop hc, by(countrycode period)
rename period year
save "1.made_data/solowsubset_5yr.dta", replace


// 1.3. MERGE WORLD BANK CLASSIFICATIONS INTO PWT
preserve
    import excel "0.source_data/CLASS_2025_10_07.xlsx", ///
        sheet("List of economies") firstrow clear
    rename Economy     country_name
    rename Code        countrycode
    rename Region      region
    rename Incomegroup income_group
    drop if missing(countrycode) | countrycode == ""
    keep countrycode region income_group
    save "1.made_data/wb_class.dta", replace
restore

use "1.made_data/solowsubset_5yr.dta", clear
merge m:1 countrycode using "1.made_data/wb_class.dta"
keep if _merge == 3
drop _merge
label var region       "World Bank region"
label var income_group "World Bank income group"
save "1.made_data/solowsubset_5yr.dta", replace


// 1.4. MERGE IAB WITH PWT
// 1:1 merge: one row per country-year in both datasets
use "1.made_data/iab_clean_wide.dta", clear
merge 1:1 countrycode year using "1.made_data/solowsubset_5yr.dta"
tab _merge
keep if _merge == 3
drop _merge

describe
summarize

// 2. Panel setup + Summary Statistics
quietly encode countrycode, gen(ccode)
tsset ccode year, delta(5)

// Solow variables
gen lngdp    = ln(rgdpe / pop)
gen dlngdp   = ln(ln(rgdpe/pop) - ln(L1.rgdpe/L1.pop))
gen lnschool = ln(hc)
gen lnn      = ln(ln(pop) - ln(L1.pop))
gen lnsave   = ln(csh_i)

// Log emigration rates for each gender category
gen lnemig_combined = ln(emig_combined)
gen lnemig_male     = ln(emig_male)
gen lnemig_female   = ln(emig_female)

label var lnemig_combined "Emigration rate, combined (ln %)"
label var lnemig_male "Emigration rate, male (ln %)"
label var lnemig_female "Emigration rate, female (ln %)"

save "1.made_data/final_iab_pwt_dataset.dta", replace

// 2.1  TABLE 1: SUMMARY STATISTICS (Year 2000, non-logged)
preserve
    keep if year == 2000 & !missing(emig_combined)

    gen gdppc = rgdpe / pop
    label var gdppc         "GDP per capita"
    label var pop           "Population"
    label var csh_i         "Investment share of GDP"
    label var hc            "Human capital index"
    label var emig_combined "Combined emigration rate (% of population)"

    tabstat gdppc pop csh_i hc emig_combined, ///
        statistics(mean sd min max n) columns(statistics) save

    matrix stats = r(StatTotal)'

    putdocx begin
    putdocx paragraph, style(Heading1)
    putdocx text ("Table 1: Summary Statistics (Year 2000)")
    putdocx table tbl = matrix(stats), rownames colnames ///
        title("Summary Statistics in Year 2000")
    putdocx save "2.output/Table1_SummaryStats_2000.docx", replace
restore

// 3. Graphs 

// 4. DIAGNOSTICS (on original variables)
quietly xtreg dlngdp L1.lngdp lnsave lnschool lnn lnemig_combined i.year i.ccode, fe
testparm i.year i.ccode

quietly xtreg dlngdp L1.lngdp lnsave lnschool lnn lnemig_combined i.ccode i.year, fe
xttest3
// We have heteroskedasticity -> use het option in xtpcse

xtserial dlngdp lnsave lnschool lnn lnemig_combined
// No serial correlation -> no corr(ar1) needed

// Non-linearity check
xtpcse dlngdp L1.lngdp lnsave lnschool lnn c.lnemig_combined##c.lnemig_combined i.ccode i.year, het

// 4.1. REVERSE CAUSALITY TEST
// xtgcause is infeasible with only 7 periods (requires T > 8).

// Run xtreg fe first to get residuals for diagnostics
quietly xtreg lnemig_combined L.lnemig_combined L.lngdp i.year, fe
xttest3
xtserial lnemig_combined lngdp
xtserial lnemig_combined dlngdp
// Heteroskedasticity -> het; serial correlation -> corr(ar1)

// REVERSE CAUSALITY: does lagged lngdp (GDP level) predict emigration?
quietly xtpcse lnemig_combined L.lnemig_combined L.lngdp i.year, het corr(ar1)
estimates store granger_lngdp_combined

// REVERSE CAUSALITY: does lagged dlngdp (GDP growth) predict emigration?
quietly xtpcse lnemig_combined L.lnemig_combined L.dlngdp i.year, het corr(ar1)
estimates store granger_dlngdp_combined

// NON-LINEARITY: quadratic dlngdp term

quietly xtpcse lnemig_combined L.lnemig_combined c.L.dlngdp##c.L.dlngdp i.year, het corr(ar1)
estimates store granger_nl_combined

// Export all Reverse Causality results
etable, estimates(granger_lngdp_combined granger_dlngdp_combined granger_nl_combined ) ///
	keep(lnemig_combined L.lnemig_combined L1.lngdp c.L.dlngdp##c.L.dlngdp lnsave lnschool lnn) ///
    mstat(N) mstat(r2) showstars showstarsnote varlabel ///
	title("Table 1.5: Reverse Causality Results") ///
    export("2.output/Table1.5_ReverseCausality.docx", replace)


// 5. We consider an interaction with income group country here. We will showcase these results after going through the main effect of emigration_rate by itself.

// 6. Regression
// ====== MAIN RESULT: COMBINED EMIGRATION ======
quietly xtpcse dlngdp lnemig_combined L1.lngdp lnsave lnschool lnn i.ccode i.year, het
estimates store full_model
etable, estimates(full_model)  ///
    keep(lnemig_combined L1.lngdp lnsave lnschool lnn) ///
    mstat(N)                                      ///
    mstat(year_fe,  label("Year fixed effects"))   ///
    mstat(cntry_fe, label("Country fixed effects"))  ///
    showstars showstarsnote varlabel                 ///
    title("Table 2: Full Regression Results") ///
    export("2.output/Table2_FullRegression.docx", replace)


// 7. WINSORIZE ALL REGRESSION VARIABLES (p1/p99)
local winsor_vars "dlngdp lngdp lnsave lnschool lnn lnemig_combined lnemig_male lnemig_female"

foreach v of local winsor_vars {
    capture drop `v'_w
    quietly sum `v', d
    gen `v'_w = `v'
    replace `v'_w = r(p1)  if `v'_w < r(p1)  & `v'_w != .
    replace `v'_w = r(p99) if `v'_w > r(p99) & `v'_w != .
    label var `v'_w "`v', winsorized p1/p99"
}

// 7.1. Use Winsorized Variables
// Main result - combined (winsorized)
quietly xtpcse dlngdp_w L1.lngdp_w lnsave_w lnschool_w lnn_w lnemig_combined_w i.ccode i.year, het
estimates store model_combined_w
estimates title: "Combined (Winsorized)"

// Export: original vs winsorized side-by-side for comparison
etable, estimates(model_combined model_combined_w) ///
	keep(lnemig_combined_w L1.lngdp_w lnsave_w lnschool_w lnn_w) /// 
    mstat(N) mstat(r2)                      ///
    mstat(year_fe,  label("Year fixed effects"))   ///
    mstat(cntry_fe, label("Country fixed effects"))  ///
    showstars showstarsnote varlabel                 ///
    title("Table 3: Winsorized Emigration Results") ///                                        ///
    export("2.output/Table3_EmigrationTable_Winsorized.docx", replace)

// 8. TABLE 2: SEQUENTIAL REGRESSION TABLE
// Builds up the specification one variable at a time. 

// Model 1: emigration rate only
quietly xtpcse dlngdp lnemig_combined i.ccode i.year, het
estimates store seq1

// Model 2: + initial income (convergence term)
quietly xtpcse dlngdp lnemig_combined L1.lngdp i.ccode i.year, het
estimates store seq2

// Model 3: + investment share
quietly xtpcse dlngdp lnemig_combined L1.lngdp lnsave i.ccode i.year, het
estimates store seq3

// Model 4: + human capital
quietly xtpcse dlngdp lnemig_combined L1.lngdp lnsave lnschool i.ccode i.year, het
estimates store seq4

// Model 5: + population growth (full Solow specification)
// this is the full specified model as above
quietly xtpcse dlngdp lnemig_combined L1.lngdp lnsave lnschool lnn i.ccode i.year, het
estimates store model_combined

etable, estimates(seq1 seq2 seq3 seq4 model_combined)  ///
	keep(lnemig_combined L1.lngdp lnsave lnschool lnn) ///
    mstat(N)                                      ///
    mstat(year_fe,  label("Year fixed effects"))   ///
    mstat(cntry_fe, label("Country fixed effects"))  ///
    showstars showstarsnote varlabel                 ///
    title("Table 4: Sequential Regression Results") ///
    export("2.output/Table4_SequentialReg.docx", replace)
	

// 9. HETEROGENEITY: INCOME GROUP INTERACTION + SUBSET
// 1=High income, 2=Low income, 3=Lower middle income, 4=Upper middle income
// We set low income as the baseline

quietly encode income_group, gen(inc_group)
label list inc_group

quietly xtpcse dlngdp L1.lngdp lnsave lnschool lnn ///
    c.lnemig_combined ib2.inc_group c.lnemig_combined#ib2.inc_group ///
    i.ccode i.year, het
estimates store model_income_interact

// Joint significance of all interaction terms
testparm c.lnemig_combined#ib2.inc_group

etable, estimates(model_combined model_income_interact) ///
	keep(lnemig_combined L1.lngdp lnsave lnschool lnn inc_group c.lnemig_combined#ib2.inc_group) /// 
    mstat(N) mstat(r2)                                  ///
    mstat(year_fe,  label("Year fixed effects"))   ///
    mstat(cntry_fe, label("Country fixed effects"))  ///
    showstars showstarsnote varlabel                     ///
	title("Table 5: Original Model vs Interaction") ///
    export("2.output/Table5_EmigrationTable_byIncomeGroup.docx", replace)
	

// 9.1  TABLE 6: INCOME GROUP COMPARISON TABLE
// Compares the full-sample result to subsets by World Bank income group.

// Column 1: Full sample (re-run to attach estadd locals cleanly)
quietly xtpcse dlngdp L1.lngdp lnsave lnschool lnn lnemig_combined i.ccode i.year, het
estimates store comp_all

// Column 2: High income countries
preserve
    keep if income_group == "High income"
    quietly xtpcse dlngdp L1.lngdp lnsave lnschool lnn lnemig_combined i.ccode i.year, het
    estimates store comp_hic
restore

// Column 3: Low income countries
preserve
    keep if income_group == "Low income"
    quietly xtpcse dlngdp L1.lngdp lnsave lnschool lnn lnemig_combined i.ccode i.year, het
    estimates store comp_lic
restore

etable, estimates(comp_all comp_hic comp_lic)                             ///
    keep(lnemig_combined L1.lngdp lnsave lnschool lnn)                   ///
    mstat(N)                                                              ///
    mstat(year_fe,  label("Year fixed effects"))                          ///
    mstat(cntry_fe, label("Country fixed effects"))                       ///
    showstars showstarsnote varlabel                                       ///
    title("Table 6: Regression Results by Income Group")                  ///
    export("2.output/Table6_IncomeGroupComparison.docx", replace)

// 10. Histogram

// 11. Gender Emigration Rates
quietly xtpcse dlngdp L1.lngdp lnsave lnschool lnn lnemig_male lnemig_female ///
    i.ccode i.year, het
estimates store model_gender

etable, estimates(model_combined model_gender) ///
	keep(lnemig_male lnemig_female L1.lngdp lnsave lnschool lnn) /// 
    mstat(N) mstat(r2)                         ///
    showstars showstarsnote varlabel            ///
    export("2.output/EmigrationTable_byGender.docx", replace)

// END
capture log close
