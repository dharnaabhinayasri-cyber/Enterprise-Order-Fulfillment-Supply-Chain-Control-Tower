ALTER USER 'root'@'localhost' IDENTIFIED BY 'NewPassword';
FLUSH PRIVILEGES;

SHOW TABLES;

/* ============================================================
   ENTERPRISE ORDER FULFILLMENT & SUPPLY CHAIN PERFORMANCE
   CONTROL TOWER
   Dataset: DataCoSupplyChainDataset / cleaned CSV
   Database: enterprise_supply_chain
   Tool: MySQL 8.x

   DATASET GRAIN:
   One row = one order line / order item.

   IMPORTANT:
   - The CSV contains 180,519 rows and 58 columns.
   - Order-level fields repeat across order lines.
   - Therefore, line-level financial metrics can be SUMmed,
     but order-level metrics must use DISTINCTCOUNT / grouping
     by order_id.
   - This project uses ONE CSV only. No fabricated supplier,
     warehouse, or inventory tables are introduced.
   ============================================================ */

/* ============================================================
   01. DATABASE SETUP
   ============================================================ */
CREATE DATABASE IF NOT EXISTS supply_chain_analysis;
USE supply_chain_analysis;

CREATE TABLE supply_chain_data_raw (
    payment_type VARCHAR(50),
    days_for_shipping_real INT,
    days_for_shipment_scheduled INT,
    benefit_per_order DECIMAL(15,2),
    sales_per_customer DECIMAL(15,2),
    delivery_status VARCHAR(100),
    late_delivery_risk INT,
    category_id INT,
    category_name VARCHAR(150),
    customer_city VARCHAR(150),
    customer_country VARCHAR(150),
    customer_id INT,
    customer_segment VARCHAR(100),
    customer_state VARCHAR(150),
    customer_zipcode VARCHAR(30),
    department_id INT,
    department_name VARCHAR(150),
    latitude DECIMAL(12,8),
    longitude DECIMAL(12,8),
    market VARCHAR(100),
    order_city VARCHAR(150),
    order_country VARCHAR(150),
    order_customer_id INT,
    order_date VARCHAR(50),
    order_id BIGINT,
    order_item_product_id INT,
    order_item_discount DECIMAL(15,2),
    order_item_discount_rate DECIMAL(10,4),
    order_item_id BIGINT,
    order_item_product_price DECIMAL(15,2),
    order_item_profit_ratio DECIMAL(10,4),
    order_item_quantity INT,
    sales DECIMAL(15,2),
    order_item_total DECIMAL(15,2),
    order_profit_per_order DECIMAL(15,2),
    order_region VARCHAR(150),
    order_state VARCHAR(150),
    order_status VARCHAR(100),
    product_card_id INT,
    product_category_id INT,
    product_name VARCHAR(255),
    product_price DECIMAL(15,2),
    product_status INT,
    shipping_date VARCHAR(50),
    shipping_mode VARCHAR(100),
    date_quality_flag VARCHAR(50),
    delivery_delay_days INT,
    on_time_flag INT,
    delay_severity VARCHAR(50),
    calculated_gross_value DECIMAL(15,2),
    discount_amount DECIMAL(15,2),
    profit_margin_pct DECIMAL(10,4),
    `year` INT,
    `month` INT,
    month_name VARCHAR(30),
    `quarter` VARCHAR(10),
    `year_month` VARCHAR(20),
    delivery_risk VARCHAR(50)
);
DESCRIBE supply_chain_data_raw;
SHOW VARIABLES LIKE 'local_infile';
SELECT COUNT(*) AS column_count
FROM information_schema.columns
WHERE table_schema = 'supply_chain_analysis'
  AND table_name = 'supply_chain_data_raw';
  
TRUNCATE TABLE supply_chain_data_raw;

LOAD DATA LOCAL INFILE
'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/dataco_supply_chain_clean.csv'
INTO TABLE supply_chain_data_raw
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

/* ============================================================
   04. BASIC DATA VALIDATION
   ============================================================ */

SELECT COUNT(*) AS total_rows
FROM supply_chain_data_raw;

SELECT COUNT(DISTINCT order_id) AS total_orders
FROM supply_chain_data_raw;

SELECT COUNT(DISTINCT order_item_id) AS total_order_items
FROM supply_chain_data_raw;

SELECT COUNT(DISTINCT customer_id) AS total_customers
FROM supply_chain_data_raw;

SELECT COUNT(DISTINCT product_card_id) AS total_products
FROM supply_chain_data_raw;

/* ============================================================
   05. DATA QUALITY CHECKS
   ============================================================ */
/* Missing values in critical identifiers */
SELECT
    SUM(customer_id IS NULL) AS missing_customer_id,
    SUM(order_id IS NULL) AS missing_order_id,
    SUM(order_item_id IS NULL) AS missing_order_item_id,
    SUM(product_card_id IS NULL) AS missing_product_id
FROM supply_chain_data_raw;

/* Duplicate order-item IDs */
SELECT
    order_item_id,
    COUNT(*) AS duplicate_count
FROM supply_chain_data_raw
GROUP BY order_item_id
HAVING COUNT(*) > 1;

/* Duplicate order + product combinations */
SELECT
    order_id,
    product_card_id,
    COUNT(*) AS line_count
FROM supply_chain_data_raw
GROUP BY order_id, product_card_id
HAVING COUNT(*) > 1;

/* Invalid quantity */
SELECT COUNT(*) AS invalid_quantity_rows
FROM supply_chain_data_raw
WHERE order_item_quantity <= 0;

/* Invalid discount rate */
SELECT COUNT(*) AS invalid_discount_rows
FROM supply_chain_data_raw
WHERE order_item_discount_rate < 0
   OR order_item_discount_rate > 1;

/* Invalid product price */
SELECT COUNT(*) AS invalid_price_rows
FROM supply_chain_data_raw
WHERE order_item_product_price < 0;

/* Invalid shipping duration */
SELECT COUNT(*) AS invalid_shipping_duration_rows
FROM supply_chain_data_raw
WHERE days_for_shipping_real < 0
   OR days_for_shipment_scheduled < 0;

/* Shipping date before order date */
SELECT COUNT(*) AS invalid_shipping_dates
FROM supply_chain_data_raw
WHERE shipping_date < order_date;

/* Invalid late-delivery flag */
SELECT COUNT(*) AS invalid_late_risk_values
FROM supply_chain_data_raw
WHERE late_delivery_risk NOT IN (0,1);

/* Invalid on-time flag */
SELECT COUNT(*) AS invalid_on_time_values
FROM supply_chain_data_raw
WHERE on_time_flag NOT IN (0,1);

/* Date-quality flag distribution */
SELECT
    date_quality_flag,
    COUNT(*) AS rows_count
FROM supply_chain_data_raw
GROUP BY date_quality_flag;

/* ============================================================
   06. BUSINESS RULE VALIDATION
   ============================================================ */

/* Recalculate gross line value */
SELECT
    COUNT(*) AS gross_value_mismatch_rows
FROM supply_chain_data_raw
WHERE ABS(
    calculated_gross_value -
    (order_item_quantity * order_item_product_price)
) > 0.01;

/* Recalculate discount amount */
SELECT
    COUNT(*) AS discount_mismatch_rows
FROM supply_chain_data_raw
WHERE ABS(
    discount_amount -
    (order_item_quantity *
     order_item_product_price *
     order_item_discount_rate)
) > 0.01;

/* Recalculate net line value */
SELECT
    COUNT(*) AS net_value_mismatch_rows
FROM supply_chain_data_raw
WHERE ABS(
    order_item_total -
    (
        order_item_quantity *
        order_item_product_price *
        (1 - order_item_discount_rate)
    )
) > 0.02;

/* Compare scheduled vs actual shipping duration */
SELECT
    COUNT(*) AS duration_mismatch_rows
FROM supply_chain_data_raw
WHERE days_for_shipping_real <>
      DATEDIFF(shipping_date, order_date);

/* ============================================================
   07. CORE EXECUTIVE KPIs
   ============================================================ */

/* Total Customers */
SELECT COUNT(DISTINCT customer_id) AS total_customers
FROM supply_chain_data_raw;

/* Total Orders */
SELECT COUNT(DISTINCT order_id) AS total_orders
FROM supply_chain_data_raw;

/* Total Order Lines */
SELECT COUNT(DISTINCT order_item_id) AS total_order_items
FROM supply_chain_data_raw;


/* Total Products */
SELECT COUNT(DISTINCT product_card_id) AS total_products
FROM supply_chain_data_raw;

/* Total Quantity */
SELECT
    SUM(order_item_quantity) AS total_quantity
FROM supply_chain_data_raw;

/* Gross Sales */
SELECT
    ROUND(SUM(calculated_gross_value), 2) AS gross_sales
FROM supply_chain_data_raw;

/* Discount Amount */
SELECT
    ROUND(SUM(discount_amount), 2) AS total_discount
FROM supply_chain_data_raw;

/* Net Sales */
SELECT
    ROUND(SUM(order_item_total), 2) AS net_sales
FROM supply_chain_data_raw;

/* Total Profit */
SELECT
    ROUND(SUM(benefit_per_order), 2) AS total_profit
FROM supply_chain_data_raw;

/* Profit Margin */
SELECT
    ROUND(
        100 * SUM(benefit_per_order)
        / NULLIF(SUM(order_item_total),0),
        2
    ) AS profit_margin_pct
FROM supply_chain_data_raw;

/* Average Order Value */
SELECT
    ROUND(
        SUM(order_item_total)
        / NULLIF(COUNT(DISTINCT order_id),0),
        2
    ) AS average_order_value
FROM supply_chain_data_raw;

/* ============================================================
   08. EXECUTIVE KPI SUMMARY
   Single query for validation/reporting.
   ============================================================ */
SELECT

    COUNT(DISTINCT customer_id) AS total_customers,

    COUNT(DISTINCT order_id) AS total_orders,

    COUNT(DISTINCT order_item_id) AS total_order_items,

    COUNT(DISTINCT product_card_id) AS total_products,

    SUM(order_item_quantity) AS total_quantity,

    ROUND(SUM(calculated_gross_value),2) AS gross_sales,

    ROUND(SUM(discount_amount),2) AS total_discount,

    ROUND(SUM(order_item_total),2) AS net_sales,

    ROUND(SUM(benefit_per_order),2) AS total_profit,

    ROUND(
        100 * SUM(benefit_per_order)
        / NULLIF(SUM(order_item_total),0),
        2
    ) AS profit_margin_pct,

    ROUND(
        SUM(order_item_total)
        / NULLIF(COUNT(DISTINCT order_id),0),
        2
    ) AS average_order_value

FROM supply_chain_data_raw;

/* ============================================================
   09. ORDER-LEVEL ANALYTICAL VIEW
   Important because one order can contain many order lines.
   ============================================================ */
CREATE OR REPLACE VIEW vw_order_summary AS

SELECT

    order_id,

    MAX(customer_id) AS customer_id,

    MIN(order_date) AS order_date,

    MAX(order_region) AS order_region,

    MAX(order_country) AS order_country,

    MAX(order_state) AS order_state,

    MAX(order_status) AS order_status,

    MAX(shipping_date) AS shipping_date,

    MAX(shipping_mode) AS shipping_mode,

    COUNT(DISTINCT order_item_id) AS order_line_count,

    SUM(order_item_quantity) AS total_quantity,

    ROUND(SUM(calculated_gross_value),2) AS gross_order_value,

    ROUND(SUM(discount_amount),2) AS discount_amount,

    ROUND(SUM(order_item_total),2) AS net_order_value,

    ROUND(SUM(benefit_per_order),2) AS order_profit,

    DATEDIFF(
        MAX(shipping_date),
        MIN(order_date)
    ) AS shipping_days,

    MAX(days_for_shipment_scheduled) AS scheduled_shipping_days,

    MAX(late_delivery_risk) AS late_delivery_risk,

    MAX(on_time_flag) AS on_time_flag,

    MAX(delay_severity) AS delay_severity,

    MAX(delivery_risk) AS delivery_risk

FROM supply_chain_data_raw

GROUP BY order_id;

/* Verify */
SELECT *
FROM vw_order_summary
LIMIT 20;

/* ============================================================
   10. ORDER STATUS ANALYSIS
   ============================================================ */
SELECT
    order_status,
    COUNT(*) AS total_orders,
    ROUND(SUM(net_order_value),2) AS net_sales,
    ROUND(AVG(net_order_value),2) AS avg_order_value
FROM vw_order_summary
GROUP BY order_status
ORDER BY total_orders DESC;

/* ============================================================
   11. CUSTOMER ANALYTICS
   ============================================================ */
CREATE OR REPLACE VIEW vw_customer_performance AS

SELECT

    customer_id,

    MAX(customer_segment) AS customer_segment,

    MAX(customer_city) AS customer_city,

    MAX(customer_state) AS customer_state,

    MAX(customer_country) AS customer_country,

    COUNT(DISTINCT order_id) AS total_orders,

    SUM(order_item_quantity) AS total_quantity,

    ROUND(SUM(order_item_total),2) AS net_sales,

    ROUND(SUM(benefit_per_order),2) AS total_profit,

    ROUND(
        SUM(order_item_total)
        / NULLIF(COUNT(DISTINCT order_id),0),
        2
    ) AS average_order_value

FROM supply_chain_data_raw

GROUP BY customer_id;

/* Top 10 customers */
SELECT *
FROM vw_customer_performance
ORDER BY net_sales DESC
LIMIT 10;

/* Repeat customers */
SELECT
    COUNT(*) AS repeat_customers
FROM vw_customer_performance
WHERE total_orders > 1;

/* One-time customers */
SELECT
    COUNT(*) AS one_time_customers
FROM vw_customer_performance
WHERE total_orders = 1;

/* ============================================================
   12. CUSTOMER VALUE SEGMENTATION
   Analytical thresholds defined for this portfolio project.
   ============================================================ */
SELECT

    customer_id,

    total_orders,

    net_sales,

    CASE

        WHEN net_sales >= 1000
             AND total_orders >= 3
            THEN 'High Value'

        WHEN net_sales >= 500
             OR total_orders >= 2
            THEN 'Medium Value'

        ELSE 'Low Value'

    END AS customer_value_segment

FROM vw_customer_performance
ORDER BY net_sales DESC;

/* ============================================================
   13. PRODUCT PERFORMANCE
   ============================================================ */
CREATE OR REPLACE VIEW vw_product_performance AS

SELECT

    product_card_id,

    MAX(product_name) AS product_name,

    MAX(category_name) AS category_name,

    MAX(department_name) AS department_name,

    MAX(product_category_id) AS product_category_id,

    MAX(product_price) AS product_price,

    MAX(product_status) AS product_status,

    SUM(order_item_quantity) AS total_quantity,

    COUNT(DISTINCT order_id) AS total_orders,

    ROUND(SUM(calculated_gross_value),2) AS gross_sales,

    ROUND(SUM(discount_amount),2) AS discount_amount,

    ROUND(SUM(order_item_total),2) AS net_sales,

    ROUND(SUM(benefit_per_order),2) AS profit,

    ROUND(
        100 * SUM(benefit_per_order)
        / NULLIF(SUM(order_item_total),0),
        2
    ) AS profit_margin_pct

FROM supply_chain_data_raw

GROUP BY product_card_id;

/* Top 10 products */
SELECT *
FROM vw_product_performance
ORDER BY net_sales DESC
LIMIT 10;

/* Lowest-sales products */
SELECT *
FROM vw_product_performance
ORDER BY net_sales ASC
LIMIT 10;

/* ============================================================
   14. CATEGORY PERFORMANCE
   ============================================================ */
SELECT

    category_name,

    COUNT(DISTINCT product_card_id) AS products,

    COUNT(DISTINCT order_id) AS orders,

    SUM(order_item_quantity) AS quantity,

    ROUND(SUM(order_item_total),2) AS net_sales,

    ROUND(SUM(benefit_per_order),2) AS profit,

    ROUND(
        100 * SUM(benefit_per_order)
        / NULLIF(SUM(order_item_total),0),
        2
    ) AS profit_margin_pct

FROM supply_chain_data_raw

GROUP BY category_name

ORDER BY net_sales DESC;

/* ============================================================
   15. DEPARTMENT PERFORMANCE
   ============================================================ */
SELECT

    department_name,

    COUNT(DISTINCT order_id) AS total_orders,

    SUM(order_item_quantity) AS total_quantity,

    ROUND(SUM(order_item_total),2) AS net_sales,

    ROUND(SUM(benefit_per_order),2) AS profit

FROM supply_chain_data_raw

GROUP BY department_name

ORDER BY net_sales DESC;

/* ============================================================
   16. DISCOUNT ANALYTICS
   ============================================================ */
SELECT

    ROUND(order_item_discount_rate * 100, 1)
        AS discount_rate_pct,

    SUM(order_item_quantity) AS quantity,

    ROUND(SUM(calculated_gross_value),2) AS gross_sales,

    ROUND(SUM(discount_amount),2) AS discount_amount,

    ROUND(SUM(order_item_total),2) AS net_sales,

    ROUND(SUM(benefit_per_order),2) AS profit

FROM supply_chain_data_raw

GROUP BY order_item_discount_rate

ORDER BY order_item_discount_rate;

/* High-discount product exceptions */
SELECT

    product_card_id,

    MAX(product_name) AS product_name,

    ROUND(
        MAX(order_item_discount_rate) * 100,
        2
    ) AS maximum_discount_pct,

    ROUND(SUM(order_item_total),2) AS net_sales,

    ROUND(SUM(benefit_per_order),2) AS profit

FROM supply_chain_data_raw

GROUP BY product_card_id

HAVING MAX(order_item_discount_rate) >= 0.30

ORDER BY maximum_discount_pct DESC;

/* ============================================================
   17. FULFILLMENT / SHIPPING ANALYTICS
   ============================================================ */
/* Overall fulfillment performance */
SELECT

    COUNT(*) AS total_orders,

    SUM(on_time_flag) AS on_time_orders,

    SUM(late_delivery_risk) AS late_orders,

    ROUND(
        100 * SUM(on_time_flag)
        / NULLIF(COUNT(*),0),
        2
    ) AS on_time_rate_pct,

    ROUND(
        AVG(shipping_days),
        2
    ) AS avg_shipping_days

FROM vw_order_summary;

/* Shipping mode performance */
SELECT

    shipping_mode,

    COUNT(*) AS total_orders,

    ROUND(AVG(shipping_days),2) AS avg_shipping_days,

    ROUND(
        100 * SUM(on_time_flag)
        / NULLIF(COUNT(*),0),
        2
    ) AS on_time_rate_pct,

    ROUND(SUM(net_order_value),2) AS net_sales

FROM vw_order_summary

GROUP BY shipping_mode

ORDER BY on_time_rate_pct DESC;

/* Delivery status */
SELECT

    delivery_status,

    COUNT(DISTINCT order_id) AS total_orders,

    ROUND(
        100 * COUNT(DISTINCT order_id)
        / SUM(COUNT(DISTINCT order_id)) OVER (),
        2
    ) AS order_share_pct

FROM supply_chain_data_raw

GROUP BY delivery_status

ORDER BY total_orders DESC;

/* Delay severity */
SELECT

    delay_severity,

    COUNT(DISTINCT order_id) AS total_orders,

    ROUND(
        AVG(delivery_delay_days),
        2
    ) AS avg_delay_days

FROM supply_chain_data_raw

GROUP BY delay_severity

ORDER BY total_orders DESC;

/* ============================================================
   18. REGIONAL OPERATIONS
   ============================================================ */
CREATE OR REPLACE VIEW vw_regional_performance AS
SELECT

    order_region,

    COUNT(DISTINCT order_id) AS total_orders,

    COUNT(DISTINCT customer_id) AS total_customers,

    SUM(order_item_quantity) AS total_quantity,

    ROUND(SUM(order_item_total),2) AS net_sales,

    ROUND(SUM(benefit_per_order),2) AS profit,

    ROUND(
        100 * SUM(benefit_per_order)
        / NULLIF(SUM(order_item_total),0),
        2
    ) AS profit_margin_pct,

    ROUND(
        AVG(delivery_delay_days),
        2
    ) AS avg_delay_days,

    ROUND(
        100 * AVG(on_time_flag),
        2
    ) AS on_time_rate_pct

FROM supply_chain_data_raw

GROUP BY order_region;

/* Verify regional performance */
SELECT *
FROM vw_regional_performance
ORDER BY net_sales DESC;

/* ============================================================
   19. MARKET PERFORMANCE
   ============================================================ */
SELECT

    market,

    COUNT(DISTINCT order_id) AS total_orders,

    COUNT(DISTINCT customer_id) AS customers,

    ROUND(SUM(order_item_total),2) AS net_sales,

    ROUND(SUM(benefit_per_order),2) AS profit,

    ROUND(
        100 * AVG(on_time_flag),
        2
    ) AS on_time_rate_pct,

    ROUND(
        AVG(delivery_delay_days),
        2
    ) AS avg_delay_days

FROM supply_chain_data_raw

GROUP BY market

ORDER BY net_sales DESC;

/* ============================================================
   20. COUNTRY PERFORMANCE
   ============================================================ */
SELECT

    order_country,

    COUNT(DISTINCT order_id) AS total_orders,

    COUNT(DISTINCT customer_id) AS customers,

    ROUND(SUM(order_item_total),2) AS net_sales,

    ROUND(
        100 * AVG(on_time_flag),
        2
    ) AS on_time_rate_pct,

    ROUND(
        AVG(delivery_delay_days),
        2
    ) AS avg_delay_days

FROM supply_chain_data_raw

GROUP BY order_country

ORDER BY net_sales DESC;

/* ============================================================
   21. MONTHLY OPERATIONS
   ============================================================ */
CREATE OR REPLACE VIEW vw_monthly_performance AS
SELECT

    YEAR(order_date) AS `year`,

    MONTH(order_date) AS `month`,

    MONTHNAME(order_date) AS month_name,

    CONCAT('Q', QUARTER(order_date)) AS quarter,

    DATE_FORMAT(order_date, '%Y-%m') AS `year_month`,

    COUNT(DISTINCT order_id) AS total_orders,

    COUNT(DISTINCT customer_id) AS total_customers,

    SUM(order_item_quantity) AS total_quantity,

    ROUND(SUM(sales), 2) AS gross_sales,

    ROUND(SUM(order_item_discount), 2) AS discount_amount,

    ROUND(SUM(order_item_total), 2) AS net_sales,

    ROUND(SUM(benefit_per_order), 2) AS profit,

    ROUND(
        100 * SUM(benefit_per_order)
        / NULLIF(SUM(order_item_total), 0),
        2
    ) AS profit_margin_pct,

    ROUND(
        100 * AVG(on_time_flag),
        2
    ) AS on_time_rate_pct,

    ROUND(
        AVG(delivery_delay_days),
        2
    ) AS avg_delay_days

FROM supply_chain_data_raw

GROUP BY
    YEAR(order_date),
    MONTH(order_date),
    MONTHNAME(order_date),
    QUARTER(order_date),
    DATE_FORMAT(order_date, '%Y-%m');

/* Monthly trend */
SELECT *
FROM vw_monthly_performance
ORDER BY `year`, `month`;

/* ============================================================
   22. MONTH-OVER-MONTH SALES GROWTH
   ============================================================ */
WITH monthly AS (
    SELECT
        `year` AS order_year,
        `month` AS order_month,
        SUM(order_item_total) AS net_sales
    FROM supply_chain_data_raw
    GROUP BY
        `year`,
        `month`
),

monthly_with_previous AS (
    SELECT
        order_year,
        order_month,
        net_sales,
        LAG(net_sales) OVER (
            ORDER BY order_year, order_month
        ) AS previous_month_sales
    FROM monthly
)

SELECT
    CONCAT(
        order_year,
        '-',
        LPAD(order_month, 2, '0')
    ) AS month_label,

    ROUND(net_sales, 2) AS net_sales,

    ROUND(previous_month_sales, 2) AS previous_month_sales,

    ROUND(
        100 * (net_sales - previous_month_sales)
        / NULLIF(previous_month_sales, 0),
        2
    ) AS mom_growth_pct

FROM monthly_with_previous

ORDER BY
    order_year,
    order_month;
    
/* ============================================================
   23. PRODUCT RANKING
   ============================================================ */
WITH product_sales AS (

    SELECT

        product_card_id,

        MAX(product_name) AS product_name,

        MAX(category_name) AS category_name,

        SUM(order_item_total) AS net_sales,

        SUM(benefit_per_order) AS profit

    FROM supply_chain_data_raw

    GROUP BY product_card_id
),

ranked_products AS (

    SELECT

        *,

        RANK() OVER (
            ORDER BY net_sales DESC
        ) AS revenue_rank,

        RANK() OVER (
            ORDER BY profit DESC
        ) AS profit_rank

    FROM product_sales
)

SELECT

    product_card_id,

    product_name,

    category_name,

    ROUND(net_sales,2) AS net_sales,

    ROUND(profit,2) AS profit,

    revenue_rank,

    profit_rank

FROM ranked_products

ORDER BY revenue_rank;

/* ============================================================
   24. REGIONAL RANKING
   ============================================================ */
SELECT

    order_region,

    net_sales,

    on_time_rate_pct,

    avg_delay_days,

    RANK() OVER (
        ORDER BY net_sales DESC
    ) AS sales_rank,

    RANK() OVER (
        ORDER BY on_time_rate_pct DESC
    ) AS fulfillment_rank

FROM vw_regional_performance

ORDER BY sales_rank;

/* ============================================================
   25. FULFILLMENT EXCEPTION ANALYSIS
   ============================================================ */
/* Critical delays */
SELECT

    order_id,

    customer_id,

    order_region,

    order_date,

    shipping_date,

    shipping_days,

    net_order_value,

    delay_severity,

    delivery_risk

FROM vw_order_summary

WHERE shipping_days > 7

ORDER BY shipping_days DESC;

/* High delays */
SELECT

    order_id,

    customer_id,

    order_region,

    order_date,

    shipping_date,

    shipping_days,

    net_order_value,

    delay_severity

FROM vw_order_summary

WHERE shipping_days BETWEEN 4 AND 7

ORDER BY shipping_days DESC;

/* Not shipped */
SELECT

    order_id,

    customer_id,

    order_region,

    order_date,

    order_status,

    net_order_value

FROM vw_order_summary

WHERE shipping_date IS NULL;

/* ============================================================
   26. EXCEPTION CENTER VIEW
   Portfolio-ready operational exception layer.
   ============================================================ */
CREATE OR REPLACE VIEW vw_exception_center AS

SELECT

    order_id,

    customer_id,

    order_region,

    order_country,

    order_date,

    order_status,

    shipping_mode,

    shipping_date,

    shipping_days,

    net_order_value,

    delay_severity,

    delivery_risk,

    CASE

        WHEN shipping_date IS NULL
            THEN 'Fulfillment Status Review'

        WHEN shipping_days > 7
            THEN 'Critical Delivery Delay'

        WHEN shipping_days BETWEEN 4 AND 7
            THEN 'High Delivery Delay'

        WHEN delivery_risk = 'Medium'
            THEN 'Medium Delivery Risk'

        ELSE 'No Major Exception'

    END AS exception_type,

    CASE

        WHEN shipping_date IS NULL
            THEN 'HIGH'

        WHEN shipping_days > 7
            THEN 'CRITICAL'

        WHEN shipping_days BETWEEN 4 AND 7
            THEN 'HIGH'

        WHEN delivery_risk = 'Medium'
            THEN 'MEDIUM'

        ELSE 'NORMAL'

    END AS severity

FROM vw_order_summary;

/* Exception summary */
SELECT

    exception_type,

    severity,

    COUNT(*) AS exception_orders,

    ROUND(SUM(net_order_value),2) AS affected_order_value

FROM vw_exception_center

WHERE exception_type <> 'No Major Exception'

GROUP BY exception_type, severity

ORDER BY
    CASE severity
        WHEN 'CRITICAL' THEN 1
        WHEN 'HIGH' THEN 2
        WHEN 'MEDIUM' THEN 3
        ELSE 4
    END,
    affected_order_value DESC;

/* ============================================================
   27. FINAL POWER BI DASHBOARD VIEW
   LINE-LEVEL GRAIN
   Use this view as the primary Power BI fact table.

   IMPORTANT:
   - Financial line metrics can be SUMmed.
   - Orders/customers must use DISTINCTCOUNT.
   ============================================================ */
CREATE OR REPLACE VIEW vw_supply_chain_dashboard AS

SELECT

    /* Order */

    order_id,
    order_date,
    order_status,

    /* Customer */

    customer_id,
    customer_segment,
    customer_city,
    customer_state,
    customer_country,

    /* Geography */

    market,
    order_city,
    order_country,
    order_state,
    order_region,
    latitude,
    longitude,

    /* Product */

    product_card_id,
    product_name,
    category_id,
    category_name,
    product_category_id,
    department_id,
    department_name,
    product_price,
    product_status,

    /* Order line */

    order_item_id,
    order_item_product_id,
    order_item_quantity,
    order_item_product_price,
    order_item_discount_rate,

    /* Commercial metrics */

    calculated_gross_value AS gross_line_sales,

    discount_amount AS discount_amount,

    order_item_total AS net_line_sales,

    benefit_per_order AS profit,

    order_item_profit_ratio,

    profit_margin_pct,

    /* Fulfillment */

    shipping_date,
    shipping_mode,
    days_for_shipping_real,
    days_for_shipment_scheduled,
    delivery_delay_days,
    on_time_flag,
    late_delivery_risk,
    delivery_status,
    delay_severity,
    delivery_risk,

    /* Payment */

    payment_type,

/* =========================
   DATE ATTRIBUTES
   ========================= */
`year`,
`month`,
month_name,
quarter
FROM supply_chain_data_raw;

/* Verify final dashboard view */
SELECT *
FROM vw_supply_chain_dashboard
LIMIT 20;

/* ============================================================
   28. FINAL EXECUTIVE CONTROL-TOWER QUERY
   Use this to validate your Power BI KPI cards.
   =========================================================== */
SELECT

    COUNT(DISTINCT order_id) AS total_orders,

    COUNT(DISTINCT customer_id) AS total_customers,

    COUNT(DISTINCT product_card_id) AS total_products,

    SUM(order_item_quantity) AS total_quantity,

    ROUND(SUM(calculated_gross_value),2) AS gross_sales,

    ROUND(SUM(discount_amount),2) AS discount_amount,

    ROUND(SUM(order_item_total),2) AS net_sales,

    ROUND(SUM(benefit_per_order),2) AS total_profit,

    ROUND(
        100 * SUM(benefit_per_order)
        / NULLIF(SUM(order_item_total),0),
        2
    ) AS profit_margin_pct,

    ROUND(
        SUM(order_item_total)
        / NULLIF(COUNT(DISTINCT order_id),0),
        2
    ) AS average_order_value,

    ROUND(
        100 * AVG(on_time_flag),
        2
    ) AS on_time_rate_pct,

    ROUND(
        100 * AVG(late_delivery_risk),
        2
    ) AS late_delivery_risk_pct,

    ROUND(
        AVG(delivery_delay_days),
        2
    ) AS average_delivery_delay_days

FROM supply_chain_data_raw;