--import tables from excel:
CREATE TABLE products (
	Product_ID int,	
	Product_Name varchar(50),	
	Product_Category varchar(50),	
	Product_Cost numeric,	
	Product_Price numeric
)

CREATE TABLE inventory (
	Store_ID int,	
	Product_ID int,	
	Stock_On_Hand int
)

CREATE TABLE sales (
	Sale_ID int,
	Date_Of_Transaction date,	
	Store_ID int,	
	Product_ID int,	
	Units_sold int
)

CREATE TABLE stores(
	Store_ID int,
	Store_Name varchar(100),
	Store_City varchar(50),
	Store_Location varchar(50),
	Store_Open_Date date
)

--preview tables:
SELECT *
FROM products
LIMIT 10

SELECT *
FROM inventory
LIMIT 10

SELECT *
FROM stores
LIMIT 10

SELECT *
FROM sales
LIMIT 10

--total revenue:
SELECT
	CAST(SUM(product_price * units_sold) AS money) AS revenue
FROM sales
INNER JOIN products ON 
	 sales.product_id = products.product_id
INNER JOIN stores ON 
	sales.store_id = stores.store_id
	
--total profit:
SELECT
	CAST(SUM((product_price - product_cost) * units_sold) AS money) AS total_profit
FROM sales
INNER JOIN products ON
	sales.product_id = products.product_id
			
--total units sold:
SELECT 
	SUM(units_sold) AS total_units_sold
FROM sales

--total inventory:
SELECT 
	SUM(stock_on_hand) AS stock 
FROM inventory
WHERE stock_on_hand is not NULL
	
--Cost of sales
SELECT 
	CAST(SUM(product_cost * stock_on_hand) AS money) AS inventory_cost
FROM inventory
INNER JOIN products	ON
	inventory.product_id = products.product_id
	
--Most profitable product categories:
SELECT 
	product_category,
	CAST(ROUND(AVG((product_price - product_cost) * units_sold),2) AS money) AS avg_profit,
	CAST(SUM((product_price - product_cost) * units_sold) AS money) AS store_profit
FROM sales
INNER JOIN products ON
	sales.product_id = products.product_id
GROUP BY product_category
ORDER BY
	store_profit DESC,
	product_category;
	
--product inventory:
SELECT 
	CASE WHEN 
		product_name IS NULL 
		THEN 'All_products' 
		ELSE product_name 
	END,
	SUM(stock_on_hand) AS stock 
FROM inventory
INNER JOIN products ON
	inventory.product_id = products.product_id
GROUP BY ROLLUP(product_name)
ORDER BY product_name;
	
--Profit across stores by product category:
WITH store_profits AS(
	SELECT
		store_id,
		SUM((product_price - product_cost) * units_sold) AS store_profit
	FROM sales
	INNER JOIN products ON
		sales.product_id = products.product_id
	GROUP BY store_id
)			
SELECT
	LTRIM(REPLACE(store_name,'Maven Toys','') )AS "Store Name",
	product_category AS "Product Category",
	CAST(SUM((product_price - product_cost) * units_sold) AS money) AS "Profit"
FROM sales
INNER JOIN stores ON
	sales.store_id = stores.store_id
INNER JOIN products ON
	sales.product_id = products.product_id
INNER JOIN store_profits ON
	stores.store_id = store_profits.store_id
GROUP BY 
	store_name,
	product_category
ORDER BY "Profit" DESC
LIMIT 10;

--Seasonal Trends:

--Units Sold over Time:
SELECT 
	DATE_PART('year',"date_of_transaction") AS "year",
	DATE_PART('month',"date_of_transaction") AS "month", 
	TO_CHAR(SUM(units_sold),'FM9G999G999') AS units
FROM sales
GROUP BY 
	"month",
	"year"
ORDER BY 
	"year",
	"month";
	
--Units Sold over time by store:
WITH per_store AS(
	SELECT 
		store_id,
		SUM(units_sold) AS total_units
	FROM sales
	GROUP BY store_id
)
SELECT 
	store_name,
	per_store.total_units AS total_units
	--ROUND(per_store.total_units * 100/SUM(total_units) OVER(), 2) || '%' AS pct_of_total
FROM per_store
INNER JOIN stores ON
	per_store.store_id = stores.store_id
ORDER BY total_units DESC;
	
--Revenue by location
SELECT
	store_location, 
	CAST(SUM(product_price * units_sold) AS money) AS revenue
FROM sales
INNER JOIN products ON 
	sales.product_id = products.product_id
INNER JOIN stores ON 
	sales.store_id = stores.store_id
GROUP BY store_location
ORDER BY revenue DESC;
	
--Revenue over time
SELECT 
	EXTRACT(year FROM "date_of_transaction") AS "year",
	EXTRACT(month FROM "date_of_transaction") AS "month", 
	CAST(SUM(product_price * units_sold) AS money) AS revenue
FROM sales
INNER JOIN products ON 
	sales.product_id = products.product_id
INNER JOIN stores ON 
	sales.store_id = stores.store_id
GROUP BY 
	"year",
	"month"
ORDER BY 
	"year",
	"month";
	
--Revenue by store and product
SELECT
	store_name,
	product_name, 
	CAST(SUM(product_price * units_sold) AS money) AS revenue
FROM sales
INNER JOIN products ON 
	 sales.product_id = products.product_id
INNER JOIN stores ON 
	sales.store_id = stores.store_id
GROUP BY 
	store_name,
	product_name
ORDER BY 
	revenue DESC,
	product_name
LIMIT 5;
	
--Revenue by store and product category
SELECT
	store_name,
	product_category, 
	CAST(SUM(product_price * units_sold) AS money) AS revenue
FROM sales
INNER JOIN products ON 
	 sales.product_id = products.product_id
INNER JOIN stores ON 
	sales.store_id = stores.store_id
GROUP BY 
	store_name,
	product_category
ORDER BY 
	revenue DESC,
	product_category	
LIMIT 5;

--Cost of inventory
WITH store_total AS(
	SELECT 
		store_id,
		SUM(product_cost * stock_on_hand) AS inventory_cost
	FROM inventory
	INNER JOIN products	ON
		inventory.product_id = products.product_id
		GROUP BY store_id
)
SELECT
	product_name AS "Product Name", 
	CAST(SUM(product_cost * stock_on_hand) AS money) AS "Inventory Cost"
	--ROUND(SUM((product_cost * stock_on_hand *100) / inventory_cost), 2) || '%' AS "Percent of Store Inventory Cost"
FROM products
INNER JOIN inventory ON
	products.product_id = inventory.product_id
INNER JOIN stores ON
	inventory.store_id = stores.store_id
INNER JOIN store_total ON
	inventory.store_id = store_total.store_id
--WHERE store_name = 'Maven Toys Aguascalientes 1'--Select store here
GROUP BY product_name
ORDER BY
	"Inventory Cost" DESC,
	product_name
LIMIT 5;

--Profit by product
SELECT
	product_name, 
	CAST(SUM((product_price - product_cost) * units_sold) AS money) AS total_profit
FROM sales
INNER JOIN products ON 
	 sales.product_id = products.product_id
INNER JOIN stores ON 
	sales.store_id = stores.store_id
GROUP BY 
	product_name
ORDER BY 
	total_profit DESC,
	product_name
LIMIT 5;

--Revenue by product
SELECT
	product_name, 
	CAST(SUM(product_price * units_sold) AS money) AS revenue
FROM sales
INNER JOIN products ON 
	 sales.product_id = products.product_id
INNER JOIN stores ON 
	sales.store_id = stores.store_id
GROUP BY 
	product_name
ORDER BY 
	revenue DESC,
	product_name
LIMIT 5;