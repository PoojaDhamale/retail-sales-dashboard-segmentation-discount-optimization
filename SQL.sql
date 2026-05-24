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

-- ================================
-- 2. Remove Old Column
-- ================================

ALTER TABLE sales 
DROP COLUMN discount_percent;

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
    WHEN discount = 0 THEN 'No Discount'
    WHEN discount <= 5 THEN '0-5%'
    WHEN discount <= 15 THEN '5-15%'
    ELSE '15%+'
  END AS discount_bucket,
  ROUND(SUM(s.quantity * p.price), 2) AS revenue
FROM sales s
JOIN products p ON s.product_id = p.product_id
GROUP BY discount_bucket
ORDER BY revenue DESC;

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
-- 15. Customer Type (New vs Old)
-- ================================

SELECT 
CASE 
  WHEN s.sale_date - c.signup_date <= 90 THEN 'New Customer'
  ELSE 'Old Customer'
END AS customer_type,
SUM(s.quantity * p.price) AS revenue
FROM sales s
JOIN customers c ON s.customer_id = c.customer_id
JOIN products p ON s.product_id = p.product_id
GROUP BY customer_type;

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
-- ================================

WITH rfm AS (
  SELECT
    c.customer_id,
    MAX(s.sale_date) AS last_purchase,
    COUNT(DISTINCT s.transaction_id) AS frequency,
    SUM(s.quantity * p.price) AS monetary
  FROM sales s
  JOIN customers c ON s.customer_id = c.customer_id
  JOIN products p ON s.product_id = p.product_id
  GROUP BY c.customer_id
)
SELECT *,
  CASE
    WHEN frequency >= 10 AND monetary > 50000 THEN 'High Value'
    WHEN frequency >= 5 THEN 'Medium Value'
    ELSE 'Low Value'
  END AS customer_segment
FROM rfm;

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
