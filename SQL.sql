-- ================================
-- 1. Add Discount Column
-- ================================

ALTER TABLE sales 
ADD COLUMN discount NUMERIC(5,2);

UPDATE sales
SET discount =
    CASE
        WHEN discount_percent ~ '^[0-9]+$'
        THEN discount_percent::NUMERIC
        ELSE 0
    END;

-- Note: ~25% of rows have NULL/non-numeric discount_percent.
-- Treated as 0% discount (no discount applied) rather than dropped,
-- since a missing discount value is the more conservative and
-- defensible default for revenue calculations.

-- ================================
-- 2. Remove Old Column
-- ================================

ALTER TABLE sales 
DROP COLUMN discount_percent;

-- ================================
-- 2b. Data Quality Fix — Invalid Quantities
-- ================================
-- Data audit found 9,254 rows (18.5% of all transactions) with
-- quantity = -1. Every negative value
-- is exactly -1 with the same discount-null rate as valid rows, which
-- is the signature of synthetic data noise, not real return transactions.
-- Removing them once at the source rather than repeating
-- "WHERE quantity > 0" across every downstream query.

DELETE FROM sales
WHERE quantity <= 0;

-- ================================
-- 3. Full Transaction View
-- ================================

SELECT 
    s.transaction_id,
    s.sale_date,

    c.customer_id,
    c.customer_name,
    c.age,
    c.city,

    p.product_id,
    p.product_name,
    p.category,
    p.price,

    st.store_id,
    st.store_city,
    st.store_type,

    s.quantity,

    (p.price * s.quantity) AS gross_amount,
    ROUND((p.price * s.quantity * (1 - s.discount/100.0)), 2) AS net_sales_amount

FROM sales s
JOIN customers c ON s.customer_id = c.customer_id
JOIN products p ON s.product_id = p.product_id
JOIN stores st ON s.store_id = st.store_id;

-- ================================
-- 4. Total Revenue
-- ================================

SELECT 
SUM(p.price * s.quantity) AS total_revenue
FROM sales s
JOIN products p ON s.product_id = p.product_id;

-- ================================
-- 5. Monthly Revenue
-- ================================

SELECT 
DATE_TRUNC('month', s.sale_date) AS month,
SUM(s.quantity * p.price) AS total_revenue
FROM sales s
JOIN products p ON s.product_id = p.product_id
GROUP BY month
ORDER BY month;

-- ================================
-- 6. Revenue by Category
-- ================================

SELECT
  p.category,
  SUM(s.quantity * p.price) AS revenue
FROM sales s
JOIN products p ON s.product_id = p.product_id
GROUP BY p.category
ORDER BY revenue DESC;

-- ================================
-- 7. Top 10 Customers
-- ================================

SELECT 
c.customer_name,
SUM(s.quantity * p.price) AS total_spent
FROM sales s
JOIN customers c ON s.customer_id = c.customer_id
JOIN products p ON s.product_id = p.product_id
GROUP BY c.customer_name
ORDER BY total_spent DESC
LIMIT 10;

-- ================================
-- 8. Customer Purchase Frequency
-- ================================

SELECT 
customer_id,
COUNT(transaction_id) AS frequency
FROM sales
GROUP BY customer_id
ORDER BY frequency DESC;

-- ================================
-- 9. Average Order Value (AOV) 
-- ================================

SELECT 
ROUND(SUM(s.quantity * p.price) / COUNT(DISTINCT s.transaction_id), 2) AS avg_order_value
FROM sales s
JOIN products p ON s.product_id = p.product_id;



-- ================================
-- 10. Revenue by Store City
-- ================================

SELECT 
st.store_city,
SUM(s.quantity * p.price) AS revenue
FROM sales s
JOIN stores st ON st.store_id = s.store_id
JOIN products p ON s.product_id = p.product_id
GROUP BY st.store_city
ORDER BY revenue DESC;

-- ================================
-- 11. Store Type Comparison
-- ================================

SELECT 
st.store_type,
COUNT(DISTINCT s.transaction_id) AS total_transactions,
SUM(s.quantity * p.price) AS revenue
FROM sales s
JOIN stores st ON st.store_id = s.store_id
JOIN products p ON s.product_id = p.product_id
GROUP BY st.store_type
ORDER BY revenue DESC;

-- ================================
-- 12. Revenue After Discount
-- ================================

SELECT 
ROUND(SUM(s.quantity * p.price * (1 - s.discount/100.0)), 2) AS revenue_after_discount
FROM sales s
JOIN products p ON s.product_id = p.product_id;

-- ================================
-- 13. Discount Impact Analysis
-- ================================

SELECT
  CASE
    WHEN s.discount <= 0  THEN '0%'
    WHEN s.discount <= 5  THEN '1-5%'
    WHEN s.discount <= 10 THEN '6-10%'
    WHEN s.discount <= 15 THEN '11-15%'
    WHEN s.discount <= 20 THEN '16-20%'
    WHEN s.discount <= 30 THEN '21-30%'
    ELSE 'Above 30%'
  END AS discount_range,
  ROUND(SUM(s.quantity * p.price * (1 - s.discount/100.0)), 2) AS net_revenue
FROM sales s
JOIN products p ON s.product_id = p.product_id
GROUP BY discount_range
ORDER BY MIN(s.discount);

-- ================================
-- 14. Sales by Weekday (Sorted)
-- ================================

SELECT 
TO_CHAR(sale_date, 'Day') AS weekday,
COUNT(*) AS transactions
FROM sales
GROUP BY weekday, EXTRACT(DOW FROM sale_date)
ORDER BY EXTRACT(DOW FROM sale_date);

-- ================================
-- 15. Conversion Speed (Fast vs Slow Converter)
-- ================================
-- Fast Converter = customer's FIRST purchase within 90 days of signup.
-- Matches the Power BI "Conversion Speed" column.

WITH first_purchase AS (
  SELECT customer_id, MIN(sale_date) AS first_sale_date
  FROM sales
  GROUP BY customer_id
),
customer_speed AS (
  SELECT
    c.customer_id,
    CASE
      WHEN fp.first_sale_date - c.signup_date <= 90 THEN 'Fast Converter'
      ELSE 'Slow Converter'
    END AS conversion_speed
  FROM customers c
  JOIN first_purchase fp ON c.customer_id = fp.customer_id
)
SELECT
  cs.conversion_speed,
  COUNT(DISTINCT cs.customer_id) AS customers,
  ROUND(SUM(s.quantity * p.price * (1 - s.discount/100.0)), 2) AS net_revenue
FROM customer_speed cs
JOIN sales s ON s.customer_id = cs.customer_id
JOIN products p ON s.product_id = p.product_id
GROUP BY cs.conversion_speed;

-- ================================
-- 16. Running Revenue (Window Function)
-- ================================

SELECT
  sale_date,
  SUM(quantity * price) OVER (ORDER BY sale_date) AS running_revenue
FROM sales s
JOIN products p ON s.product_id = p.product_id;

-- ================================
-- 17. Product Revenue Ranking
-- ================================

SELECT
  p.product_name,
  SUM(s.quantity * p.price) AS revenue,
  RANK() OVER (ORDER BY SUM(s.quantity * p.price) DESC) AS revenue_rank
FROM sales s
JOIN products p ON s.product_id = p.product_id
GROUP BY p.product_name;

-- ================================
-- 18. Customer Lifetime Value (CLV)
-- ================================

SELECT
  c.customer_id,
  c.customer_name,
  ROUND(SUM(s.quantity * p.price * (1 - s.discount/100.0)), 2) AS lifetime_value
FROM sales s
JOIN customers c ON s.customer_id = c.customer_id
JOIN products p ON s.product_id = p.product_id
GROUP BY c.customer_id, c.customer_name
ORDER BY lifetime_value DESC;

-- ================================
-- 19. RFM Segmentation 
-- ================================.

WITH rfm_raw AS (
  SELECT
    c.customer_id,
    MAX(s.sale_date)                       AS last_purchase_date,
    (SELECT MAX(sale_date) FROM sales)
      - MAX(s.sale_date)                   AS recency_days,
    COUNT(DISTINCT s.transaction_id)       AS frequency,
    SUM(s.quantity * p.price
        * (1 - s.discount/100.0))          AS monetary
  FROM sales s
  JOIN customers c ON s.customer_id = c.customer_id
  JOIN products p ON s.product_id = p.product_id
  GROUP BY c.customer_id
),
rfm_scored AS (
  SELECT
    customer_id,
    recency_days,
    frequency,
    monetary,
    -- Lower recency_days = more recent = better score, so order ASC
    NTILE(4) OVER (ORDER BY recency_days ASC)  AS r_score,
    NTILE(4) OVER (ORDER BY frequency DESC)    AS f_score,
    NTILE(4) OVER (ORDER BY monetary DESC)     AS m_score
  FROM rfm_raw
),
seg AS (
  SELECT *,
    (r_score + f_score + m_score) AS rfm_total,
    CASE
      WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 2 THEN 'Champions'
      WHEN m_score <= 2 AND f_score <= 2 THEN 'High Value'
      WHEN r_score >= 3 THEN 'At Risk / Churning'
      ELSE 'Medium Value'
    END AS segment
  FROM rfm_scored
)
SELECT
  segment,
  COUNT(*) AS customers,
  ROUND(AVG(monetary), 2) AS avg_monetary,
  ROUND(AVG(frequency), 1) AS avg_frequency,
  ROUND(AVG(recency_days), 0) AS avg_recency_days,
  SUM(monetary) AS total_revenue,
  ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 2) AS revenue_share
FROM seg
GROUP BY segment
ORDER BY total_revenue DESC;

-- ================================
-- 20. Repeat vs One-time Customers
-- ================================

SELECT customer_type, COUNT(*) AS customers
FROM (
    SELECT customer_id,
        CASE 
            WHEN COUNT(transaction_id) = 1 THEN 'One-time'
            ELSE 'Repeat'
        END AS customer_type
    FROM sales
    GROUP BY customer_id
) t
GROUP BY customer_type;

-- ================================
-- 21. Month-over-Month Growth
-- ================================

WITH monthly AS (
  SELECT
    DATE_TRUNC('month', sale_date) AS month,
    SUM(quantity * price) AS revenue
  FROM sales s
  JOIN products p ON s.product_id = p.product_id
  GROUP BY month
)
SELECT
  month,
  revenue,
  revenue - LAG(revenue) OVER (ORDER BY month) AS mom_growth
FROM monthly;
