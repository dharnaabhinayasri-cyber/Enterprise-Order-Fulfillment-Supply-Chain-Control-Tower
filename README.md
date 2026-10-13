# Enterprise Order Fulfillment & Supply Chain Analytics

## Executive Summary

This project analyses order fulfillment, delivery performance, sales, profitability, and logistics exceptions using the DataCo Supply Chain dataset.

The workflow combines Python and Pandas for data preparation and feature engineering, MySQL for data validation and business analysis, and Power BI with DAX for interactive operational reporting.

The analysis is designed to help supply chain stakeholders answer five key questions:

1. How consistently are orders delivered on time?
2. Which regions and shipping modes have higher delivery-delay exposure?
3. Which products and categories generate revenue and profit?
4. How do discounts relate to profitability?
5. Which delayed or at-risk orders should be prioritized for investigation?

**Dataset grain:** One row represents an order line, not necessarily one unique order.

**Tools:** Python, Pandas, MySQL, Power Query, Power BI, DAX, Excel.

**Deliverable:** A multi-page supply chain analytics report covering executive KPIs, fulfillment performance, commercial analysis, regional logistics, and exception management.

## Analytical Approach

Raw data → Data-quality checks → Cleaning and feature engineering → SQL analysis → Power BI data modeling → KPI validation → Business recommendations.

## Key Operational Findings

1. **Delivery Performance:** The observed on-time delivery rate was [X%] across [N] eligible orders during [reporting period].

2. **Delay Concentration:** [Region or shipping mode] had the highest observed delay rate ([X%]), based on [N] eligible orders.

3. **Commercial Performance:** [Category] generated the highest sales, while [category or sub-category] had the weakest profit margin.

4. **Discount Exposure:** Orders in the [discount band] segment had a profit margin of [X%], compared with [Y%] in the comparison segment.

5. **Operational Priorities:** [N] orders met the project's exception criteria and were prioritized according to [actual prioritization rule].

## Recommended Actions

- Investigate recurring delivery delays in the segments with the highest validated delay rates.
- Review shipping-mode performance alongside delivery volume and order mix.
- Monitor profitability alongside sales when evaluating commercial performance.
- Establish an exception review process and track operational KPIs over time.

*All reported findings should be calculated from the validated dataset. Observational patterns do not, by themselves, establish causation.*