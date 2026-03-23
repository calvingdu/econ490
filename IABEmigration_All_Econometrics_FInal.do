// Emigration Rate with Solow Model
// Data: IAB Brain Drain Dataset + Penn World Tables 11.0 + World Bank dataset
// IAB coverage: 1980, 1985, 1990, 1995, 2000, 2005, 2010

// 1. File setup 
cd "C:\Users\ianpa\OneDrive\Desktop\ECON 490\Econometrics"
capture mkdir "1.made_data"
capture mkdir "2.output"

capture log close
log using "2.output/IABEmigrationAll.log", text replace


// 2. Load Data 
use "1.made_data/final_iab_pwt_dataset.dta", clear

// 2.1 Table of Summary Statistics

*drop observations that do not include our dependent variable of choice
drop if emig_combined ==.

label var rgdpe "Expenditure-side real GDP at chained PPPs (in mil. 2021US$)"
label var csh_i "Share of Gross Capital Formation at current PPPs (Savings)"
label var hc "Human capital index"

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

foreach v of local winsor_vars {
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
	title("Income Group Interaction Model Comparison") ///
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
	title("Gender Effects Model Comparison") ///
    export("2.output/EmigrationTable_byGender.docx", replace)


// 7. Use Winsorized Variables

// Main result - combined (winsorized)
xtpcse dlngdp_w L1.lngdp_w lnsave_w lnschool_w lnn_w lnemig_combined_w i.ccode i.year, het
estimates store model_combined_w
estimates title: "Combined (Winsorized)"

// Gender (winsorized)
xtpcse dlngdp_w L1.lngdp_w lnsave lnschool_w lnn lnemig_male_w lnemig_female_w ///
    i.ccode i.year, het
estimates store model_gender_w
estimates title: "Gender (Winsorized)"

// Export: original vs winsorized side-by-side for comparison
etable, estimates(model_combined model_combined_w model_gender model_gender_w) ///
    mstat(N) mstat(r2)                                                          ///
    showstars showstarsnote varlabel                                             ///
	keep (dlngdp L1.lngdp lnsave lnschool lnn lnemig_combined lnemig_male lnemig_female dlngdp_w L1.lngdp_w lnsave_w lnschool_w lnn_w lnemig_combined_w lnemig_male_w lnemig_female_w) ///
	title("Winsorized Model Comparison") ///
    export("2.output/EmigrationTable_Winsorized.docx", replace)
	
*winsorized improves fit
	
	
// 8. Regression Series

*Regression Step 1
xtpcse dlngdp_w lnemig_combined_w i.ccode i.year, het
estimates store step1
estimates title: "1"

*Regression Step 2
xtpcse dlngdp_w lnemig_combined_w L1.lngdp_w i.ccode i.year, het
estimates store step2
estimates title: "2"

*Regression Step 3
xtpcse dlngdp_w lnemig_combined_w L1.lngdp_w lnsave_w i.ccode i.year, het
estimates store step3
estimates title: "3"

*Regression Step 4
xtpcse dlngdp_w lnemig_combined_w L1.lngdp_w lnsave_w lnschool_w i.ccode i.year, het
estimates store step4
estimates title: "4"

etable, estimates(step1 step2 step3 step4) ///
    mstat(N) mstat(r2)                                                          ///
    showstars showstarsnote varlabel                                             ///
	keep(dlngdp_w L1.lngdp_w lnsave_w lnschool_w lnn_w lnemig_combined_w) ///
    export("2.output/SteppedRegression.docx", replace)


	
// 9. Graph Outputs

*change our scheme to economist
set scheme s2color

// Regular Relationship Graphs

*Combined
twoway(scatter dlngdp lnemig_combined) (lfit dlngdp lnemig_combined), ytitle("GDP Growth (ln)") title("Emigration vs. GDP Growth", position(11)) ///
legend( label(1 "Observations") label(2 "Line of Fit")) note("Scatterplot of GDP Growth (ln) and Combined Emigration Rate for all observations")
graph export "2.output/CombinedScatterdlngdp.png", as(png) replace

*Upper Middle Income
preserve
keep if income_group=="Upper middle income"
twoway(scatter dlngdp lnemig_combined) (lfit dlngdp lnemig_combined), ytitle("GDP Growth (ln)") title("Emigration vs. GDP Growth (Upper Middle Income)",position(11)) ///
legend( label(1 "Observations") label(2 "Line of Fit")) note("Scatterplot of GDP Growth (ln) and Emigration Rate for Observations in the Upper Middle Income Category")
graph export "2.output/UMIncomeScatterdlngdp.png", as(png) replace
restore

*Male
twoway(scatter dlngdp lnemig_male) (lfit dlngdp lnemig_male), ytitle("GDP Growth (ln)") title("Male Emigration vs. GDP Growth",position(11)) ///
legend( label(1 "Observations") label(2 "Line of Fit")) note("Scatterplot of GDP Growth (ln) and Male Emigration Rate for all observations")
graph export "2.output/MaleScatterdlngdp.png", as(png) replace

*Female
twoway(scatter dlngdp lnemig_female) (lfit dlngdp lnemig_female), ytitle("GDP Growth (ln)") title("Female Emigration vs. GDP Growth",position(11)) ///
legend( label(1 "Observations") label(2 "Line of Fit")) note("Scatterplot of GDP Growth (ln) and Female Emigration Rate for all observations")
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
    title("Combined Emigration and GDP Growth",position(11)) ///
    xtitle("Combined Emigration Rate") ///
    ytitle("GDP Growth") ///
    legend(label(1 "Observations") label(2 "Line of Fit")) ///
	note("OLS predicted relationship between Emigration and GDP Growth")
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
    title("Male Emigration and GDP Growth",position(11)) ///
    xtitle("Male Emigration Rate") ///
    ytitle("GDP Growth") ///
    legend(label(1 "Observations") label(2 "Partial Fit")) ///
	note("OLS predicted relationship between Male Emigration and GDP Growth")
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
    title("Female Emigration and GDP Growth",position(11)) ///
    xtitle("Female Emigration Rate ") ///
    ytitle("GDP Growth") ///
    legend(label(1 "Observations") label(2 "Line of Fit")) ///
	note("OLS predicted relationship between Female Emigration and GDP Growth")
graph export "2.output/FemaleAVPlot.png", as(png) replace
drop e_y_female e_x_female

// Regression Relationship Graphs

// Main Relationship

quietly xtpcse dlngdp_w L1.lngdp_w lnsave lnschool_w lnn lnemig_combined i.ccode i.year, het
predict yhat, xb
*scatter yhat and lnemig_combined
twoway(scatter yhat lnemig_combined) (lfit yhat lnemig_combined), title("Combined Emigration Linearity Analysis",position(11)) ///
legend( label(1 "Predicted Values") label(2 "Line of Fit")) ///
note("Scatterplot of Emigration and GDP Growth to assess linearity of relationship")
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
twoway(scatter yhat lnemig_male) (lfit yhat lnemig_male), title("Male Emigration Linearity Analysis",position(11)) ///
legend( label(1 "Predicted Values") label(2 "Line of Fit")) ///
note("Scatterplot of Male Emigration and GDP Growth to assess linearity of relationship")
graph export "2.output/MaleRelateGraph.png", as(png) replace
*Female Graph
twoway(scatter yhat lnemig_female) (lfit yhat lnemig_female), title("Female Emigration Linearity Analysis",position(11)) ///
legend( label(1 "Predicted Values") label(2 "Line of Fit")) ///
note("Scatterplot of Female Emigration and GDP Growth to assess linearity of relationship")
graph export "2.output/FemaleRelateGraph.png", as(png) replace

// Histograms Global and by Income Level

*global histogram of emigration frequency
histogram lnemig_combined, color(lavender) lcolor(black) ///
ytitle("Frequency") xtitle("Emigration Rate, Combined (ln%)") title ("Emigration Frequency",position(11)) ///
note("Histogram displaying frequency distribution of the natural log of emigration rate")
graph export "2.output/GlobalHistogram.png", as(png) replace

*Upper Middle Income Histogram
histogram lnemig_combined if income_group == "Upper middle income", color(yellow) lcolor(black) ///
ytitle("Frequency") xtitle("Emigration Rate, Combined (ln%)") ///
title("Emigration Frequency",position(11)) subtitle("Upper Middle Income", position(11)) ///
note("Histogram displaying frequency distribution of the natural log of emigration rate for observations in the Upper Middle Income category")
graph export "2.output/UpperMiddleIncomeHistogram.png", as(png) replace

*combined emigration frequency by income level
twoway (histogram lnemig_combined if income_group=="Low income", color(red) lcolor(black)) ///
(histogram lnemig_combined if income_group=="Lower middle income", color(orange) lcolor(black)) ///
(histogram lnemig_combined if income_group=="Upper middle income", color(yellow) lcolor(black)) ///
(histogram lnemig_combined if income_group=="High income", color(green) lcolor(black)), title("Emigration Frequency",position(11)) ///
subtitle("by Income Level",position(11)) ytitle("Frequency") xtitle("Emigration Rate, Combined (ln%)") ///
legend( label(1 "Low Income") label(2 "Lower Middle Income") label(3 "Upper Middle Income") label(4 "High Income")) ///
note("Histogram displaying frequency distribution of the natural log of emigration rate by income category")
graph export "2.output/IncomeLevelHistogram.png", as(png) replace

*Male and Female Emigration Frequency Comparison Histogram
twoway (histogram lnemig_male, color(orange) lcolor(black)) (histogram lnemig_female, color(blue) lcolor(black)), ///
ytitle("Frequency") xtitle("Emigration Rate (ln%)") legend( label(1 "Male") label(2 "Female")) ///
title("Emigration Frequency",position(11)) subtitle("by Gender",position(11)) ///
note("Histogram displaying frequency distribution of the natural log of emigration rate by gender")
graph export "2.output/GenderHistogram.png", as(png) replace

// END
capture log close
