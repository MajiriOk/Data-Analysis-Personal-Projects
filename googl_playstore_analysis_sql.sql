CREATE TABLE playstore_data(
	App_id int,
	App_name varchar(50),
	Category varchar(50),
	Rating numeric,
	Reviews bigint,
	Installs bigint,
	App_type varchar(15),
	Price numeric,
	Content_rating varchar(50),
	Genres varchar(50),
	App_size_kb numeric,
	Update_month varchar(20),
	Update_year varchar(4));

ALTER TABLE playstore_data
ALTER COLUMN App_name TYPE VARCHAR(255);

--EDA (Exploratory Data Analysis)

-- Overview of the data
SELECT *
FROM playstore_data

SELECT App_name
FROM playstore_data

--count of records
SELECT COUNT(DISTINCT App_id) AS Unique_app_id
FROM playstore_data

--Check for missing values
SELECT COUNT(*) AS Missing_values
FROM playstore_data
WHERE App_name IS null OR Rating IS null OR Genres IS NULL

--Group by app type and analyze key metrics
SELECT 
	Category, 
	ROUND(AVG(Installs), 2) AS Avg_installs, 
    ROUND(AVG(Price), 2) AS Avg_price, 
    ROUND(AVG(Rating), 2) AS Avg_rating
	
FROM playstore_data
GROUP BY Category
LIMIT 15

--Determine number of apps per category
SELECT Category, COUNT(*) AS Number_of_apps_per_category
FROM playstore_data
GROUP BY Category
ORDER BY Number_of_apps_per_category DESC
LIMIT 15

--Determine number of apps per genre
SELECT Genres, COUNT(*) AS Number_of_apps_per_genre
FROM playstore_data
GROUP BY Genres
ORDER BY Number_of_apps_genre DESC
LIMIT 15

--Overview of app ratings
SELECT MIN(Rating) AS Minimum_rating,
	   MAX(Rating) AS Maximum_rating,
	   ROUND(AVG(Rating), 2) AS Average_rating
FROM playstore_data

--Average rating per install
SELECT App_name, AVG (Rating / Installs) AS Average_rating_per_install
FROM playstore_data
GROUP BY App_name 
ORDER BY Average_rating_per_install DESC

--Conversion rate (installs from reviews)
SELECT 
    App_name, 
    COALESCE(Installs / NULLIF(Reviews, 0), 0) AS Conversion_rate
FROM playstore_data;


--FINDING INSIGHTS FOR STAKEHOLDER

--Determine if paid apps have higher ratings than free apps
SELECT 
    CASE
        WHEN Price > 0 THEN 'PAID'
        ELSE 'FREE'
    END AS App_type,
    ROUND(AVG(Rating), 2) AS Average_rating
FROM 
    playstore_data
GROUP BY 
    CASE
        WHEN Price > 0 THEN 'PAID'
        ELSE 'FREE'
    END;

-- Top 10 performing app categories
SELECT 
    Category,
    SUM(Installs) AS Total_downloads,
    ROUND(AVG(Rating), 2) AS Average_rating
FROM 
    playstore_data
GROUP BY 
    Category
ORDER BY 
    Total_downloads DESC, Average_rating DESC
LIMIT 10;

--Bottom 10 performing app categories (Market to target)
SELECT 
    Category,
    SUM(Installs) AS Total_downloads,
    ROUND(AVG(Rating), 2) AS Average_rating
FROM 
    playstore_data
GROUP BY 
    Category
ORDER BY 
    Average_rating ASC, Total_downloads ASC
LIMIT 10; 

--Genres with low ratings (Market to target)
SELECT Genres, SUM(Installs) AS Total_downloads, ROUND(AVG(Rating), 2) AS Average_rating
FROM playstore_data
GROUP BY Genres
ORDER BY Average_rating ASC, Total_downloads ASC
LIMIT 10


-- Add a new column named 'rating_count' to the existing table
ALTER TABLE playstore_data
ADD COLUMN Rating_count INTEGER;

-- Update the new column with the total count of the 'Rating' column for each row
UPDATE playstore_data
SET rating_count = (SELECT COUNT(*) FROM playstore_data WHERE Rating IS NOT NULL);

--Check the top-rated apps for each category
SELECT 
    Genres, 
    App_name, 
    Rating
FROM (
    SELECT
        Genres,
        App_name,
        Rating,
        RANK() OVER (PARTITION BY Genres ORDER BY Rating DESC, rating_count DESC) AS rank
    FROM 
        playstore_data
	WHERE 
        Rating IS NOT NULL -- Filter out apps with null ratings
) AS a
WHERE 
    a.rank = 1;



