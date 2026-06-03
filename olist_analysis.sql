CREATE TABLE customers (
    customer_id VARCHAR(50) PRIMARY KEY,
    customer_unique_id VARCHAR(50),
    customer_zip_code_prefix VARCHAR(10),
    customer_city VARCHAR(100),
    customer_state CHAR(2)
);

CREATE TABLE orders (
    order_id VARCHAR(50) PRIMARY KEY,
    customer_id VARCHAR(50),
    order_status VARCHAR(50),
    order_purchase_timestamp TIMESTAMP,
    order_approved_at TIMESTAMP,
    order_delivered_carrier_date TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP
);

CREATE TABLE order_items (
    order_id VARCHAR(50),
    order_item_id INT,
    product_id VARCHAR(50),
    seller_id VARCHAR(50),
    shipping_limit_date TIMESTAMP,
    price NUMERIC(10,2),
    freight_value NUMERIC(10,2)
);

CREATE TABLE order_payments (
    order_id VARCHAR(50),
    payment_sequential INT,
    payment_type VARCHAR(50),
    payment_installments INT,
    payment_value NUMERIC(10,2)
);

CREATE TABLE order_reviews (
    review_id VARCHAR(50),
    order_id VARCHAR(50),
    review_score INT,
    review_comment_title VARCHAR(255),
    review_comment_message TEXT,
    review_creation_date TIMESTAMP,
    review_answer_timestamp TIMESTAMP
);

CREATE TABLE products (
    product_id VARCHAR(50) PRIMARY KEY,
    product_category_name VARCHAR(100),
    product_name_length NUMERIC,
    product_description_length NUMERIC,
    product_photos_qty NUMERIC,
    product_weight_g NUMERIC,
    product_length_cm NUMERIC,
    product_height_cm NUMERIC,
    product_width_cm NUMERIC
);

CREATE TABLE sellers (
    seller_id VARCHAR(50) PRIMARY KEY,
    seller_zip_code_prefix VARCHAR(10),
    seller_city VARCHAR(100),
    seller_state CHAR(2)
);

CREATE TABLE geolocation (
    geolocation_zip_code_prefix VARCHAR(10),
    geolocation_lat NUMERIC(9,6),
    geolocation_lng NUMERIC(9,6),
    geolocation_city VARCHAR(100),
    geolocation_state CHAR(2)
);

CREATE TABLE category_translation (
    product_category_name VARCHAR(100),
    product_category_name_english VARCHAR(100)
);

------------------------------------------------------------------------

-- Verify each table loaded correctly
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL
SELECT 'orders', COUNT(*) FROM orders
UNION ALL
SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL
SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL
SELECT 'order_reviews', COUNT(*) FROM order_reviews
UNION ALL
SELECT 'products', COUNT(*) FROM products
UNION ALL
SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL
SELECT 'geolocation', COUNT(*) FROM geolocation
UNION ALL
SELECT 'category_translation', COUNT(*) FROM category_translation;

-----------------------------------------------------------------------
-- EDA

-- Check 1 - NULL values in key columns of the orders table
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE order_status IS NULL) AS null_status,
    COUNT(*) FILTER (WHERE customer_id IS NULL) AS null_customer,
    COUNT(*) FILTER (WHERE order_purchase_timestamp IS NULL) AS null_purchase_date,
    COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL) AS null_delivery_date,
    COUNT(*) FILTER (WHERE order_approved_at IS NULL) AS null_approved
FROM orders;

-- Check 2 - Order status breakdown
SELECT *
FROM orders;

SELECT
    order_status,
    COUNT(*) AS order_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM orders
GROUP BY order_status
ORDER BY order_count DESC;

--Check 3 - NULL product categories
SELECT *
FROM products;

SELECT
    COUNT(*) AS total_products,
    COUNT(*) FILTER (WHERE product_category_name IS NULL) AS null_category
FROM products;


-- Check 4 - Order items with no matching order

SELECT COUNT(*) AS orphaned_items
FROM order_items oi
LEFT JOIN orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;

-- Check 5 - Date range of the dataset

SELECT
    MIN(order_purchase_timestamp) AS earliest_order,
    MAX(order_purchase_timestamp) AS latest_order
FROM orders;

----------------------------------------------------------------------------
-- ANALYSIS

-- Orders that never reached the customer
SELECT
    order_status,
    COUNT(*) AS order_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM orders
WHERE order_status IN ('canceled', 'unavailable')
GROUP BY order_status
ORDER BY order_count DESC;


-- How many distinct product categories exist in the dataset?
SELECT *
FROM category_translation;

SELECT COUNT(DISTINCT t.product_category_name_english) AS total_categories
FROM products p
JOIN category_translation t
    ON p.product_category_name = t.product_category_name;


--------------------------------------------------------------------------------------------------
-- Category Cancellation Rates
-- A CTE called category_orders that builds the raw counts we need
WITH category_orders AS (
    SELECT
        -- Get the English category name from the translation table
        t.product_category_name_english AS category,

        -- Count every order in this category, regardless of status
        COUNT(DISTINCT o.order_id) AS total_orders,

        -- Count only the cancelled orders using CASE WHEN
        -- CASE WHEN is like an IF statement: if the condition is true, return 1, else return 0
        -- SUM adds up all the 1s, giving you a count of cancelled orders
        SUM(CASE WHEN o.order_status = 'canceled' THEN 1 ELSE 0 END) AS cancelled_orders,

        -- Do the same for unavailable orders
        SUM(CASE WHEN o.order_status = 'unavailable' THEN 1 ELSE 0 END) AS unavailable_orders

    FROM orders o
    -- Join order_items to connect orders to products
    JOIN order_items oi ON o.order_id = oi.order_id
    -- Join products to get the category name in Portuguese
    JOIN products p ON oi.product_id = p.product_id
    -- Join translation table to convert Portuguese category name to English
    JOIN category_translation t ON p.product_category_name = t.product_category_name

    -- Group by category so each row in the result = one category
    GROUP BY t.product_category_name_english
)

-- Now the final SELECT reads from the CTE like it is a regular table
SELECT
    category,
    total_orders,
    cancelled_orders,
    unavailable_orders,

    -- cancelled + unavailable = all orders that never reached a customer
    cancelled_orders + unavailable_orders AS total_problem_orders,

    -- Calculate cancellation rate as a percentage
    -- Multiply by 100.0 (not 100) to force decimal division instead of integer division
    -- ROUND(..., 2) keeps two decimal places
    ROUND(cancelled_orders * 100.0 / total_orders, 2) AS cancellation_rate_pct,

    -- Same calculation including unavailable orders
    ROUND((cancelled_orders + unavailable_orders) * 100.0 / total_orders, 2) AS problem_rate_pct

FROM category_orders

-- Only show categories where at least one cancellation occurred
-- This filters out categories with zero cancellations so the list stays meaningful
WHERE cancelled_orders > 0

-- Sort by cancellation rate, highest first
ORDER BY cancellation_rate_pct DESC;


-----------------------------------------------------------------------------------------------------

-- Regional Cancellation Ranking
-- First CTE: calculate raw cancellation stats per state
WITH regional_stats AS (
    SELECT
        c.customer_state,

        -- Total orders from this state
        COUNT(DISTINCT o.order_id) AS total_orders,

        -- Cancelled orders from this state
        SUM(CASE WHEN o.order_status = 'canceled' THEN 1 ELSE 0 END) AS cancelled_orders,

        -- Unavailable orders from this state
        SUM(CASE WHEN o.order_status = 'unavailable' THEN 1 ELSE 0 END) AS unavailable_orders

    FROM orders o
    -- Join customers to get the state each order came from
    JOIN customers c ON o.customer_id = c.customer_id
    GROUP BY c.customer_state
),

-- Second CTE: calculate rates and apply window function ranking
-- This CTE reads from the first CTE, not from the raw tables
ranked_regions AS (
    SELECT
        customer_state,
        total_orders,
        cancelled_orders,
        unavailable_orders,

        -- Cancellation rate as a percentage
        ROUND(cancelled_orders * 100.0 / total_orders, 2) AS cancellation_rate_pct,

        -- RANK() is the window function
        -- OVER (ORDER BY ...) defines the window: rank all states by cancellation rate
        -- highest cancellation rate = rank 1
        -- Each state keeps its own row - nothing is collapsed
        RANK() OVER (ORDER BY cancelled_orders * 1.0 / total_orders DESC) AS rank_by_cancellation,

        -- A second ranking by raw cancelled order volume
        -- This shows you which states have the most cancellations in absolute numbers
        RANK() OVER (ORDER BY cancelled_orders DESC) AS rank_by_volume

    FROM regional_stats
)

-- Final SELECT reads from the second CTE
SELECT *
FROM ranked_regions
-- Only show states with at least 50 orders so small-sample states don't skew the ranking
WHERE total_orders >= 50
ORDER BY rank_by_cancellation;

-------------------------------------------------------------------------------------------------------

-- Revenue at Risk by Category
-- CTE 1: calculate total revenue and cancelled revenue per category
WITH category_revenue AS (
    SELECT
        t.product_category_name_english AS category,

        -- Count total orders per category
        COUNT(DISTINCT o.order_id) AS total_orders,

        -- Count cancelled orders per category
        SUM(CASE WHEN o.order_status = 'canceled' THEN 1 ELSE 0 END) AS cancelled_orders,

        -- Total revenue across all orders in this category
        -- price is stored in order_items, so we sum it here
        ROUND(SUM(oi.price), 2) AS total_revenue,

        -- Revenue specifically from cancelled orders
        -- CASE WHEN checks the order status, then returns the price if cancelled, else 0
        -- SUM adds all those cancelled prices together
        ROUND(SUM(CASE WHEN o.order_status = 'canceled' THEN oi.price ELSE 0 END), 2) AS cancelled_revenue

    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    JOIN products p ON oi.product_id = p.product_id
    JOIN category_translation t ON p.product_category_name = t.product_category_name
    GROUP BY t.product_category_name_english
),

-- CTE 2: add cancellation rate and revenue at risk percentage
-- reads from CTE 1, not from raw tables
revenue_impact AS (
    SELECT
        category,
        total_orders,
        cancelled_orders,
        total_revenue,
        cancelled_revenue,

        -- Cancellation rate by order count
        ROUND(cancelled_orders * 100.0 / total_orders, 2) AS cancellation_rate_pct,

        -- What percentage of total revenue is at risk
        -- This is a different question from cancellation rate
        -- A category can have a low cancellation rate but high revenue at risk
        -- if its products are expensive
        ROUND(cancelled_revenue * 100.0 / total_revenue, 2) AS revenue_at_risk_pct,

        -- Rank categories by cancelled revenue, highest first
        -- This is your business impact ranking
        RANK() OVER (ORDER BY cancelled_revenue DESC) AS rank_by_revenue_lost

    FROM category_revenue
    WHERE cancelled_orders > 0
)

SELECT -- category, total_revenue, cancelled_revenue, cancellation_rate_pct, revenue_at_risk_pct, rank_by_revenue_lost
FROM revenue_impact
ORDER BY rank_by_revenue_lost;
--LIMIT 15;

--------------------------------------------------------------------------------------------------------

-- Review Scores vs. Cancellation Rate
-- CTE 1: average review score per category
WITH category_reviews AS (
    SELECT
        t.product_category_name_english AS category,

        -- Average review score across all reviewed orders in this category
        -- review_score is an integer from 1 to 5
        ROUND(AVG(r.review_score), 2) AS avg_review_score,

        -- Count of reviews so we know how reliable the average is
        COUNT(r.review_id) AS review_count

    FROM order_reviews r
    -- Join to orders to get order status
    JOIN orders o ON r.order_id = o.order_id
    -- Join to order_items to get product
    JOIN order_items oi ON o.order_id = oi.order_id
    -- Join to products to get category
    JOIN products p ON oi.product_id = p.product_id
    -- Join to translation for English category name
    JOIN category_translation t ON p.product_category_name = t.product_category_name
    GROUP BY t.product_category_name_english
),

-- CTE 2: cancellation rate per category (same logic as Query Group B)
category_cancellations AS (
    SELECT
        t.product_category_name_english AS category,
        COUNT(DISTINCT o.order_id) AS total_orders,
        SUM(CASE WHEN o.order_status = 'canceled' THEN 1 ELSE 0 END) AS cancelled_orders,
        ROUND(SUM(CASE WHEN o.order_status = 'canceled' THEN 1 ELSE 0 END) * 100.0 /
            COUNT(DISTINCT o.order_id), 2) AS cancellation_rate_pct
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    JOIN products p ON oi.product_id = p.product_id
    JOIN category_translation t ON p.product_category_name = t.product_category_name
    GROUP BY t.product_category_name_english
)

-- Final SELECT: join both CTEs together on category name
-- This is a CTE-to-CTE join, not a join to a raw table
-- It works exactly the same way - you reference the CTE name like a table name
SELECT
    cc.category,
    cc.total_orders,
    cc.cancelled_orders,
    cc.cancellation_rate_pct,
    cr.avg_review_score,
    cr.review_count,

    -- Rank by cancellation rate so you can see if low review scores
    -- cluster toward the top of the cancellation ranking
    RANK() OVER (ORDER BY cc.cancellation_rate_pct DESC) AS rank_by_cancellation,

    -- Rank by review score, lowest first
    -- A low review score rank appearing alongside a high cancellation rank
    -- confirms the connection between cancellations and dissatisfaction
    RANK() OVER (ORDER BY cr.avg_review_score ASC) AS rank_by_low_review

FROM category_cancellations cc
JOIN category_reviews cr ON cc.category = cr.category
WHERE cc.cancelled_orders > 0
    AND cr.review_count >= 10
ORDER BY rank_by_cancellation;

-----------------------------------------------------------------------------------------------------

-- KPIs
SELECT
    COUNT(*) AS total_orders,
    SUM(CASE WHEN order_status = 'canceled' THEN 1 ELSE 0 END) AS cancelled_orders,
    ROUND(SUM(CASE WHEN order_status = 'canceled' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS cancellation_rate
FROM orders;