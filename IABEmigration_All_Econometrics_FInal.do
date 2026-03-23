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

// HYPOTHESIS: An increase in Emigration Rate will result in a statistically signifiant effect on Economic Growth in the Origin Country. 

// Our results show conclusive statistically significant effects when we seperate by gender, but since these are opposing effects, the main effect is not statistically significant. 

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

// 2. Load Data 
use "1.made_data/final_iab_pwt_dataset.dta", clear

// 2.1 Table of Summary Statistics

*drop observations that do not include our dependent variable of choice
drop if emig_combined ==.

label var rgdpe "Expenditure-side real GDP at chained PPPs (in mil. 2021US$)"
label var csh_i "Share of Gross Capital Formation at current PPPs (Savings)"
label var hc "Human capital index"

// Print Out a summary table
keep if year == 2000 & !missing(emig_combined)

label var pop           "Population"
label var csh_i         "Investment share of GDP"
label var hc            "Human capital index"
label var emig_combined "Combined emigration rate (% of population)"

tabstat rgdpe pop csh_i hc emig_combined emig_male emig_female, ///
	statistics(mean sd min max n) columns(statistics) save
*create and export a table of summary statistics
sum2docx rgdpe csh_i hc pop emig_combined emig_male emig_female using "2.output/TableSummaryStats", ///
replace stats(N mean(%9.2f) sd min(%9.0g) median(%9.0g) max(%9.0g)) varlabel

*create and export a table of summary statistics for year 2000
sum2docx rgdpe csh_i hc pop emig_combined emig_male emig_female using "2.output/TableSummaryStats2000" if year==2000, ///
replace stats(N mean(%9.2f) sd min(%9.0g) median(%9.0g) max(%9.0g)) varlabel


// 2.5 WINSORIZE ALL REGRESSION VARIABLES (p1/p99)
local winsor_vars "dlngdp lngdp lnsave lnschool lnn lnemig_combined lnemig_male lnemig_female"

*test if we should winsorize
foreach v of local winsor_vars {
	quietly summarize `v', detail
	local ratio_lb = round(r(p1)/r(min))
	local ratio_ub = round(r(max)/r(p99))
	display "First percentile `v' is `r(p1)'"
	display "Min `v' is `r(min)'"
	display "99th percentile `v' is `r(p99)' "
	display "Max `v' is `r(max)'"
	display "1st percentile `v' is `ratio_lb' times the minimum"
	display "Max `v' is `ratio_ub' times as much as the 99th percentile!"
}

*we should winsorize gdp (and therefore dlngdp), we could winsorize lnschool.
local winsor_vars_updated "dlngdp lngdp lnschool"

foreach v of local winsor_vars_updated {
    capture drop `v'_w
    sum `v', d
    gen `v'_w = `v'
    replace `v'_w = r(p1)  if `v'_w < r(p1)  & `v'_w != .
    replace `v'_w = r(p99) if `v'_w > r(p99) & `v'_w != .
    label var `v'_w "`v', winsorized p1/p99"
}


// 3. DIAGNOSTICS (on original variables)
xtreg dlngdp L1.lngdp lnsave lnschool lnn lnemig_combined i.year i.ccode, fe
testparm i.year i.ccode

xtreg dlngdp L1.lngdp lnsave lnschool lnn lnemig_combined i.ccode i.year, fe
xttest3
// We have heteroskedasticity -> use het option in xtpcse

xtserial dlngdp lnsave lnschool lnn lnemig_combined
// No serial correlation -> no corr(ar1) needed

// Non-linearity check
xtpcse dlngdp L1.lngdp lnsave lnschool lnn c.lnemig_combined##c.lnemig_combined i.ccode i.year, het


// 4. MAIN RESULT: COMBINED EMIGRATION
display as text "------ MAIN RESULT: Total Emigration Rate ------"

xtpcse dlngdp L1.lngdp lnsave lnschool lnn lnemig_combined i.ccode i.year, het
estimates store model_combined
estimates title: "Combined"


// 5. HETEROGENEITY: INCOME GROUP INTERACTION
// 1=High income, 2=Low income, 3=Lower middle income, 4=Upper middle income
// We set low income as the baseline

display as text "------ INCOME GROUP INTERACTION ------"
encode income_group, gen(inc_group)
label list inc_group

xtpcse dlngdp L1.lngdp lnsave lnschool lnn ///
    c.lnemig_combined ib2.inc_group c.lnemig_combined#ib2.inc_group ///
    i.ccode i.year, het
estimates store model_income_interact

// Joint significance of all interaction terms
testparm c.lnemig_combined#ib2.inc_group

etable, estimates(model_combined model_income_interact) ///
    mstat(N) mstat(r2)                                  ///
    showstars showstarsnote varlabel                     ///
    export("2.output/EmigrationTable_byIncomeGroup.docx", replace)


// 6. HETEROGENEITY: GENDER
display as text "------ GENDER: Male vs Female Emigration Rates ------"

xtpcse dlngdp L1.lngdp lnsave lnschool lnn lnemig_male lnemig_female ///
    i.ccode i.year, het
estimates store model_gender

etable, estimates(model_combined model_gender) ///
    mstat(N) mstat(r2)                         ///
    showstars showstarsnote varlabel            ///
	keep(dlngdp L1.lngdp lnsave lnschool lnn lnemig_male lnemig_female) ///
    export("2.output/EmigrationTable_byGender.docx", replace)


// 7. Use Winsorized Variables

// Main result - combined (winsorized)
xtpcse dlngdp_w L1.lngdp_w lnsave lnschool_w lnn lnemig_combined i.ccode i.year, het
estimates store model_combined_w
estimates title: "Combined (Winsorized)"

// Gender (winsorized)
xtpcse dlngdp_w L1.lngdp_w lnsave lnschool_w lnn lnemig_male lnemig_female ///
    i.ccode i.year, het
estimates store model_gender_w
estimates title: "Gender (Winsorized)"

// Export: original vs winsorized side-by-side for comparison
etable, estimates(model_combined model_combined_w model_gender model_gender_w) ///
    mstat(N) mstat(r2)                                                          ///
    showstars showstarsnote varlabel                                             ///
	keep (dlngdp L1.lngdp lnsave lnschool lnn lnemig_combined lnemig_male lnemig_female) ///
    export("2.output/EmigrationTable_Winsorized.docx", replace)
	
	
// 8. Regression Series
*Regression Step 1
xtpcse dlngdp_w lnemig_combined i.ccode i.year, het
estimates store step1
estimates title: "1"

*Regression Step 2
xtpcse dlngdp_w lnemig_combined L1.lngdp_w i.ccode i.year, het
estimates store step2
estimates title: "2"

*Regression Step 3
xtpcse dlngdp_w lnemig_combined L1.lngdp_w lnsave i.ccode i.year, het
estimates store step3
estimates title: "3"

*Regression Step 4
xtpcse dlngdp_w lnemig_combined L1.lngdp_w lnsave lnschool_w i.ccode i.year, het
estimates store step4
estimates title: "4"

etable, estimates(step1 step2 step3 step4) ///
    mstat(N) mstat(r2)                                                          ///
    showstars showstarsnote varlabel                                             ///
	keep(dlngdp L1.lngdp lnsave lnschool lnn lnemig_combined) ///
    export("2.output/SteppedRegression.docx", replace)
	
// 9. Graph Outputs

// Regular Relationship Graphs

*Combined
twoway(scatter dlngdp lnemig_combined) (lfit dlngdp lnemig_combined), title("Emigration vs. GDP Growth") ///
legend( label(1 "Observations") label(2 "Line of Fit"))
graph export "2.output/CombinedScatterdlngdp.png", as(png) replace

*Upper Middle Income
preserve
keep if income_group=="Upper middle income"
twoway(scatter dlngdp lnemig_combined) (lfit dlngdp lnemig_combined), title("Emigration vs. GDP Growth") ///
legend( label(1 "Observations") label(2 "Line of Fit"))
graph export "2.output/MIncomeScatterdlngdp.png", as(png) replace
restore

*Male
twoway(scatter dlngdp lnemig_male) (lfit dlngdp lnemig_male), title("Male Emigration vs. GDP Growth") ///
legend( label(1 "Observations") label(2 "Line of Fit"))
graph export "2.output/MaleScatterdlngdp.png", as(png) replace

*Female
twoway(scatter dlngdp lnemig_female) (lfit dlngdp lnemig_female), title("Female Emigration vs. GDP Growth") ///
legend( label(1 "Observations") label(2 "Line of Fit"))
graph export "2.output/FemaleScatterdlngdp.png", as(png) replace

// 9.1 Partial Regression Plots
// xtpcse predict only supports xb, so residuals = actual - predicted (manual)

// Combined Emigration
quietly xtpcse dlngdp_w L1.lngdp_w lnsave lnschool_w lnn i.ccode i.year, het
predict double yhat_y_comb, xb
gen double e_y_comb = dlngdp_w - yhat_y_comb
drop yhat_y_comb

quietly xtpcse lnemig_combined L1.lngdp_w lnsave lnschool_w lnn i.ccode i.year, het
predict double yhat_x_comb, xb
gen double e_x_comb = lnemig_combined - yhat_x_comb
drop yhat_x_comb

twoway (scatter e_y_comb e_x_comb) ///
       (lfit    e_y_comb e_x_comb), ///
    title("Combined Emigration and GDP Growth") ///
    xtitle("Combined Emigration Rate") ///
    ytitle("GDP Growth") ///
    legend(label(1 "Observations") label(2 "Line of Fit"))
graph export "2.output/CombinedAVPlot.png", as(png) replace
drop e_y_comb e_x_comb


// Male (with controls including lnemig_female)
quietly xtpcse dlngdp_w L1.lngdp_w lnsave lnschool_w lnn lnemig_female i.ccode i.year, het
predict double yhat_y_male, xb
gen double e_y_male = dlngdp_w - yhat_y_male
drop yhat_y_male

quietly xtpcse lnemig_male L1.lngdp_w lnsave lnschool_w lnn lnemig_female i.ccode i.year, het
predict double yhat_x_male, xb
gen double e_x_male = lnemig_male - yhat_x_male
drop yhat_x_male

twoway (scatter e_y_male e_x_male) ///
       (lfit    e_y_male e_x_male), ///
    title("Male Emigration and GDP Growth") ///
    xtitle("Male Emigration Rate") ///
    ytitle("GDP Growth") ///
    legend(label(1 "Observations") label(2 "Partial Fit"))
graph export "2.output/MaleAVPlot.png", as(png) replace
drop e_y_male e_x_male

// Female (with controls including lnemig_male)
quietly xtpcse dlngdp_w L1.lngdp_w lnsave lnschool_w lnn lnemig_male i.ccode i.year, het
predict double yhat_y_female, xb
gen double e_y_female = dlngdp_w - yhat_y_female
drop yhat_y_female

quietly xtpcse lnemig_female L1.lngdp_w lnsave lnschool_w lnn lnemig_male i.ccode i.year, het
predict double yhat_x_female, xb
gen double e_x_female = lnemig_female - yhat_x_female
drop yhat_x_female

twoway (scatter e_y_female e_x_female) ///
       (lfit    e_y_female e_x_female), ///
    title("Female Emigration and GDP Growth") ///
    xtitle("Female Emigration Rate ") ///
    ytitle("GDP Growth") ///
    legend(label(1 "Observations") label(2 "Line of Fit"))
graph export "2.output/FemaleAVPlot.png", as(png) replace
drop e_y_female e_x_female

// Regression Relationship Graphs

// Main Relationship

quietly xtpcse dlngdp_w L1.lngdp_w lnsave lnschool_w lnn lnemig_combined i.ccode i.year, het
predict yhat, xb
*scatter yhat and lnemig_combined
twoway(scatter yhat lnemig_combined) (lfit yhat lnemig_combined), title("Combined Emigration Linearity Analysis") ///
legend( label(1 "Predicted Values") label(2 "Line of Fit"))
*save the graph
graph export "2.output/CombinedRelateGraph.png", as(png) replace


*drop yhat
drop yhat

// Gendered Relationships

*Combined Graph
quietly xtpcse dlngdp_w L1.lngdp_w lnsave lnschool_w lnn lnemig_male lnemig_female ///
    i.ccode i.year, het
predict yhat, xb

*Male Graph
twoway(scatter yhat lnemig_male) (lfit yhat lnemig_male), title("Male Emigration Linearity Analysis") ///
legend( label(1 "Predicted Values") label(2 "Line of Fit"))
graph export "2.output/MaleRelateGraph.png", as(png) replace
*Female Graph
twoway(scatter yhat lnemig_female) (lfit yhat lnemig_female), title("Female Emigration Linearity Analysis") ///
legend( label(1 "Predicted Values") label(2 "Line of Fit"))
graph export "2.output/FemaleRelateGraph.png", as(png) replace

// Histograms Global and by Income Level

*global histogram of emigration frequency
histogram lnemig_combined, color(blue) lcolor(black) ///
ytitle("Frequency") xtitle("Emigration Rate, Combined (ln%)") title ("Emigration Frequency")
graph export "2.output/GlobalHistogram.png", as(png) replace

*Upper Middle Income Histogram
histogram lnemig_combined if income_group == "Upper middle income", color(yellow) lcolor(black) ///
ytitle("Frequency") xtitle("Emigration Rate, Combined (ln%)") title ("Emigration Frequency Upper Middle Income")
graph export "2.output/UpperMiddleIncomeHistogram.png", as(png) replace

*combined emigration frequency by income level
twoway (histogram lnemig_combined if income_group=="Low income", color(red) lcolor(black)) ///
(histogram lnemig_combined if income_group=="Lower middle income", color(orange) lcolor(black)) ///
(histogram lnemig_combined if income_group=="Upper middle income", color(yellow) lcolor(black)) ///
(histogram lnemig_combined if income_group=="High income", color(green) lcolor(black)), title("Emigration Frequency by Income Level") ///
ytitle("Frequency") xtitle("Emigration Rate, Combined (ln%)") ///
legend( label(1 "Low Income") label(2 "Lower Middle Income") label(3 "Upper Middle Income") label(4 "High Income"))
graph export "2.output/IncomeLevelHistogram.png", as(png) replace

*Male and Female Emigration Frequency Comparison Histogram
twoway (histogram lnemig_male, color(orange) lcolor(black)) (histogram lnemig_female, color(blue) lcolor(black)), ///
ytitle("Frequency") xtitle("Emigration Rate (ln%)") legend( label(1 "Male") label(2 "Female")) title("Emigration Frequency by Gender")
graph export "2.output/GenderHistogram.png", as(png) replace

// END
capture log close
