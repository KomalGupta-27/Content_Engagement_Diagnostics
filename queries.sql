
-- SETUP 1: Create the database
CREATE DATABASE content_db;

-- SETUP 2: Create an external table over the cleaned Parquet file
-- Replace YOUR-BUCKET with your S3 bucket name.

CREATE EXTERNAL TABLE content_db.articles (
  url string,
  title string,
  author string,
  subtitle string,
  claps bigint,
  responses bigint,
  reading_time double,
  tag string,
  publish_date date,
  has_subtitle bigint,
  title_length bigint,
  title_word_count bigint,
  has_number bigint,
  is_question bigint,
  is_how_to bigint,
  subtitle_word_count bigint,
  day_of_week string,
  publish_month bigint,
  is_weekend bigint,
  length_bucket string,
  publication string,
  author_article_count bigint,
  log_claps double,
  high_impact bigint,
  has_response bigint
)
STORED AS PARQUET
LOCATION 's3://komal-project-content-engagement/clean/';


-- CHECK: Row count and a sample (expect 45,851 rows)
SELECT COUNT(*) AS total_rows
FROM content_db.articles;

SELECT *
FROM content_db.articles
LIMIT 10;


-- Q1. Overview: how skewed is engagement overall?
SELECT
  COUNT(*) AS articles,
  approx_percentile(claps, 0.5) AS median_claps,
  ROUND(AVG(claps), 1) AS avg_claps,
  MAX(claps) AS max_claps,
  ROUND(100.0 * SUM(CASE WHEN claps = 0 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_zero_claps
FROM content_db.articles;


-- Q2. Tag performance: which topics get the most engagement?
SELECT
  tag,
  COUNT(*) AS articles,
  approx_percentile(claps, 0.5) AS median_claps,
  ROUND(100.0 * AVG(has_response), 1) AS pct_with_response
FROM content_db.articles
GROUP BY tag
ORDER BY median_claps DESC;


-- Q3. Length cohorts: does article length matter?
-- Result: long 17.2%, medium 11.6%, short 4.7% high-impact rate.
SELECT
  length_bucket,
  COUNT(*) AS articles,
  approx_percentile(claps, 0.5) AS median_claps,
  ROUND(100.0 * AVG(high_impact), 1) AS high_impact_pct
FROM content_db.articles
GROUP BY length_bucket
ORDER BY high_impact_pct DESC;

-- Q4. Publish day: does the day of the week matter?
SELECT
  day_of_week,
  COUNT(*) AS articles,
  approx_percentile(claps, 0.5) AS median_claps,
  ROUND(100.0 * AVG(high_impact), 1) AS high_impact_pct
FROM content_db.articles
GROUP BY day_of_week
ORDER BY high_impact_pct DESC;


-- Q5. Title and subtitle features: high-impact rate with vs without
-- Result: "how to" 13.7% vs 10.0%; question 8.6% vs 10.3%;
--         number in title 10.1% vs 10.1%.
SELECT
  'has_number' AS feature,
  ROUND(100.0 * AVG(CASE WHEN has_number = 1 THEN high_impact END), 1) AS with_pct,
  ROUND(100.0 * AVG(CASE WHEN has_number = 0 THEN high_impact END), 1) AS without_pct
FROM content_db.articles
UNION ALL
SELECT
  'is_question',
  ROUND(100.0 * AVG(CASE WHEN is_question = 1 THEN high_impact END), 1),
  ROUND(100.0 * AVG(CASE WHEN is_question = 0 THEN high_impact END), 1)
FROM content_db.articles
UNION ALL
SELECT
  'is_how_to',
  ROUND(100.0 * AVG(CASE WHEN is_how_to = 1 THEN high_impact END), 1),
  ROUND(100.0 * AVG(CASE WHEN is_how_to = 0 THEN high_impact END), 1)
FROM content_db.articles
UNION ALL
SELECT
  'has_subtitle',
  ROUND(100.0 * AVG(CASE WHEN subtitle_word_count > 0 THEN high_impact END), 1),
  ROUND(100.0 * AVG(CASE WHEN subtitle_word_count = 0 THEN high_impact END), 1)
FROM content_db.articles;

-- Q6. Top publications by median claps (minimum 50 articles)
SELECT
  publication,
  COUNT(*) AS articles,
  approx_percentile(claps, 0.5) AS median_claps
FROM content_db.articles
GROUP BY publication
HAVING COUNT(*) >= 50
ORDER BY median_claps DESC
LIMIT 15;


-- Q7. Claps concentration: what share of all claps does each decile get?
-- Decile 1 = the top 10% of articles by claps.
WITH deciles AS (
  SELECT
    claps,
    NTILE(10) OVER (ORDER BY claps DESC) AS decile
  FROM content_db.articles
)
SELECT
  decile,
  SUM(claps) AS total_claps,
  ROUND(100.0 * SUM(claps) / SUM(SUM(claps)) OVER (), 1) AS pct_of_all_claps
FROM deciles
GROUP BY decile
ORDER BY decile;


-- Q8. Top 3 articles per tag
SELECT tag, title, claps
FROM (
  SELECT
    tag,
    title,
    claps,
    ROW_NUMBER() OVER (PARTITION BY tag ORDER BY claps DESC) AS rn
  FROM content_db.articles
) ranked
WHERE rn <= 3
ORDER BY tag, claps DESC;
