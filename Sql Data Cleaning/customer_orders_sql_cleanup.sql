CREATE TABLE customer_orders (
    order_id INTEGER,
    customer_id TEXT,
    customer_name TEXT,
    email TEXT,
    order_date TEXT,
    product_category TEXT,
    order_amount TEXT,
    payment_method TEXT,
    country TEXT,
    state TEXT,
    signup_date TEXT
);

SELECT *
FROM customer_orders

-- Create clean staging table
CREATE TABLE customer_orders_clean AS
SELECT *
FROM customer_orders;

SELECT *
FROM customer_orders_clean

--Standardize text fields
UPDATE customer_orders_clean
SET
    customer_name = TRIM(customer_name),
    product_category = LOWER(TRIM(product_category)),
    payment_method = LOWER(TRIM(payment_method)),
    country = LOWER(TRIM(country)),
    state = LOWER(TRIM(state));


-- Fix Category Inconsistencies
UPDATE customer_orders_clean
SET product_category = 'electronics'
WHERE product_category IN ('electrnics', 'electronics');

UPDATE customer_orders_clean
SET product_category = 'home & kitchen'
WHERE product_category IN ('home&kitchen', 'home & kitchen');

-- Clean Monetary Values
-- Step 1: Replace invalid text values in order_amount with NULL
-- The dataset contains 'nan' values stored as text
-- These must be converted to NULL before changing the data type
UPDATE customer_orders_clean
SET order_amount = NULL
WHERE order_amount ILIKE 'nan' OR order_amount IS NULL;

-- Step 2: Convert order_amount from TEXT to NUMERIC
-- Remove currency symbols ($), commas, and extra spaces before casting
-- This ensures accurate numerical storage for calculations
ALTER TABLE customer_orders_clean
ALTER COLUMN order_amount TYPE NUMERIC
USING REPLACE(REPLACE(TRIM(order_amount), '$', ''), ',', '')::NUMERIC;

-- Handle Invalid dates
UPDATE customer_orders_clean
SET order_date = NULL
WHERE order_date = '2023-13-01';

-- Convert Dates to DATE TYPE
SELECT DISTINCT order_date
FROM customer_orders_clean
ORDER BY order_date;

-- Order Date
-- Standardize mixed date formats in the order_date column
-- The column currently contains TEXT values stored in multiple formats
-- This CASE statement detects each format using regex and converts it properly
SELECT DISTINCT signup_date
FROM customer_orders_clean
ORDER BY signup_date;

UPDATE customer_orders_clean
SET order_date =
    CASE
        -- YYYY-MM-DD
        WHEN order_date ~ '^\d{4}-\d{2}-\d{2}$'
            THEN TO_DATE(order_date, 'YYYY-MM-DD')

        -- MM/DD/YYYY
        WHEN order_date ~ '^\d{2}/\d{2}/\d{4}$'
            THEN TO_DATE(order_date, 'MM/DD/YYYY')

        -- DD-MM-YYYY
        WHEN order_date ~ '^\d{2}-\d{2}-\d{4}$'
            THEN TO_DATE(order_date, 'DD-MM-YYYY')

        ELSE NULL
    END;

-- Signup Date
UPDATE customer_orders_clean
SET signup_date =
    CASE
        -- YYYY-MM-DD
        WHEN signup_date ~ '^\d{4}-\d{2}-\d{2}$'
            THEN TO_DATE(order_date, 'YYYY-MM-DD')

        -- MM/DD/YYYY
        WHEN signup_date ~ '^\d{2}/\d{2}/\d{4}$'
            THEN TO_DATE(order_date, 'MM/DD/YYYY')

        -- DD-MM-YYYY
        WHEN signup_date ~ '^\d{2}-\d{2}-\d{4}$'
            THEN TO_DATE(order_date, 'DD-MM-YYYY')

        ELSE NULL
    END;

-- Handle Missing Values
-- Replace missing or empty email values with a standardized placeholder
UPDATE customer_orders_clean
SET email = 'unknown'
WHERE email IS NULL OR email = '';

-- Replace missing or empty payment_method values with 'unknown'
UPDATE customer_orders_clean
SET payment_method = 'unknown'
WHERE payment_method IS NULL OR payment_method = '';

-- Normalize Country and State values
UPDATE customer_orders_clean
SET country = 'united states'
WHERE country IN ('usa', 'us', 'u.s.', 'united states');


UPDATE customer_orders_clean
SET state = 'california'
WHERE state IN ('ca', 'california');

UPDATE customer_orders_clean
SET state = 'new york'
WHERE state IN ('ny', 'new york');

UPDATE customer_orders_clean
SET state = 'texas'
WHERE state IN ('tx', 'texas');

UPDATE customer_orders_clean
SET state = 'pennsylvania'
WHERE state IN ('pa', 'pennsylvania');

-- Normalize payment method
UPDATE customer_orders_clean
SET payment_method = 'credit card'
WHERE payment_method IN ('creditcard', 'credit card');

UPDATE customer_orders_clean
SET payment_method = 'pay pal'
WHERE payment_method IN ('paypal', 'pay pal');
