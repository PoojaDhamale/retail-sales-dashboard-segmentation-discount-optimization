# 🛒 Retail Sales Performance, Customer Segmentation & Discount Optimization

An end-to-end retail analytics project: raw transactional data is cleaned, modeled, and analyzed in SQL — including RFM-based customer segmentation — with key findings explored further through an interactive Power BI dashboard covering revenue performance, customer insights, and discount impact.

---

## Overview

|             |                                                                                                                        |
| ----------- | ---------------------------------------------------------------------------------------------------------------------- |
| **Problem** | Understand what drives revenue, which customers matter most, and whether discounting is helping or hurting net revenue |
| **Data**    | 5,000 customers · 1,000 products · 50 stores · 50,000 raw transactions (synthetic, India-based retail)                 |
| **Tools**   | SQL (PostgreSQL) for cleaning, feature creation, and analysis · Power BI (DAX) for the dashboard                       |
| **Output**  | A multi-page interactive dashboard covering sales performance, customer behavior, and discount strategy                |

---

## Data Cleaning & Quality Decisions

Real data-quality issues were found and handled deliberately, not silently dropped:

- **~25% of rows had a null or non-numeric `discount_percent` value.** Rather than dropping these rows, they were treated as 0% discount — the more conservative, defensible default for revenue calculations, since a missing discount is more likely a data gap than a true unknown discount. As a result, the "0%" discount group in the dashboard includes these imputed rows (see Limitations).
- **9,254 rows (18.5% of all transactions) had `quantity = -1`.** Every negative-quantity row was exactly -1 (never -2, -5, etc.) with the same null-discount rate as valid rows — the signature of synthetic data noise rather than real product returns. These rows were removed once at the data-cleaning stage rather than filtering them out repeatedly in every downstream query.
- After cleaning, **~40,700 valid transactions** remain (the dashboard's "41K Total Orders" figure), which is about 8 transactions per customer on average across the 5,000 customers.

---

## SQL Analysis (`SQL.sql`)

Beyond basic aggregation, the analysis uses:

- **CTEs** to build a full RFM (Recency, Frequency, Monetary) segmentation pipeline in one readable query, rather than one long nested query
- **`NTILE(4)`** to score every customer into quartiles on recency, frequency, and monetary value independently, then combine those scores into named segments (Champions, High Value, At Risk/Churning, Medium Value)
- **`RANK()`** for product revenue ranking, and **`LAG()`** for month-over-month revenue growth
- A running-revenue window function (`SUM(...) OVER (ORDER BY sale_date)`) to track cumulative revenue over time
- Separate queries for Customer Lifetime Value, discount-bucket revenue impact, new-vs-returning customer revenue split, and store-type performance comparison

---

## SQL-Only Insights

Some analysis lives only in `SQL.sql` and isn't currently represented as a dashboard visual — noted here for transparency:

- **RFM Customer Segmentation:** Every customer is scored into quartiles on Recency, Frequency, and Monetary value, then grouped into segments (Champions, High Value, At Risk/Churning, Medium Value) with revenue share per segment.
- **Customer Lifetime Value (CLV):** Per-customer lifetime spend.
- **Month-over-Month Revenue Growth:** Calculated via `LAG()`.

---

## Dashboard Highlights

### Sales Overview

- **₹5.86bn total revenue vs ₹5.13bn net revenue (after discounts)** — a gap of about ₹0.73bn (~12.5% of total revenue), driven by discounting.
- **Net revenue shows a gradual downward trend over time**, which points to the need for regular performance monitoring.
- **Revenue is spread fairly evenly:** the five named categories (Beauty, Electronics, Clothing, Grocery, Home) each contribute roughly 14–15% of net revenue, and the top 10 products together contribute only about 2.5%. No single product or category dominates, so product concentration risk is low.
- **"Uncategorized" is the largest single bucket (~28%, ₹1.43bn)** — flagged as a data-quality gap in the source `category` field rather than a real business category, and called out directly in the dashboard rather than hidden.

### Customer Insights

- **Conversion speed:** 79% of customers (4K of 5K) are **Fast Converters** — their first purchase came within 90 days of signing up. The remaining 21% are **Slow Converters**. This reflects historical conversion speed, not current new-customer acquisition volume.
- **Customer concentration is low:** the top 10% of customers contribute about 19% of net revenue, and the top single customer is only ~₹3.2M, so the business is not overly dependent on a small handful of accounts.
- **Purchase-frequency segmentation (by net revenue):**

  | Purchase Type | Purchases per customer | Net revenue | Share |
  | ------------- | ---------------------- | ----------- | ----- |
  | Medium        | 6–10                   | ₹3.17bn     | ~62%  |
  | High          | More than 10           | ₹1.50bn     | ~29%  |
  | Low           | 1–5                    | ₹0.45bn     | ~9%   |

- **Geographic skew:** only 5 cities are geographically mapped, but they represent **71% of net revenue** (₹3.63bn). The remaining **29% (₹1.5bn)** comes from customers with no city recorded in the source data — a substantial share of revenue that currently cannot be mapped or analyzed geographically.

### Discount Impact

Net revenue by discount level (values are rounded):

| Discount range | Net revenue |
| -------------- | ----------- |
| 0%             | ₹2.2bn      |
| 1–5%           | ₹0.7bn      |
| 6–10%          | ₹0.7bn      |
| 11–15%         | ₹0.6bn      |
| 16–20%         | ₹0.6bn      |
| Above 30%      | ₹0.4bn      |

- About **43% of net revenue (₹2.2bn)** falls in the 0% group, and about 57% comes from discounted sales.
- Net revenue declines as discount depth increases. Orders at the deepest discount level (50%) still contribute about ₹0.4bn (~8% of net revenue), so the margin cost of deep discounts is worth reviewing.
- Discounts in the data come in fixed levels (0, 5, 10, 15, 20 and 50%), so there are no transactions in the 21–30% band.
- **Store-type revenue** is split across High Street (32.6%), Mall (17.3%), and Online (15.9%) — but the single largest share, **34.1%, falls into "Unknown"** store type, exceeding every identified channel. This is surfaced as a data-quality gap rather than smoothed over.

---

## Key DAX Definitions

**Conversion Speed** — classifies customers by how quickly they made their first purchase after signing up:

```dax
Conversion Speed =
VAR FirstPurchaseDate =
    CALCULATE(
        MIN(fact_sales[sale_date]),
        FILTER(
            fact_sales,
            fact_sales[customer_id] = dim_customers[customer_id]
        )
    )
RETURN
IF(
    DATEDIFF(dim_customers[signup_date], FirstPurchaseDate, DAY) <= 90,
    "Fast Converter",
    "Slow Converter"
)
```

**Purchase Type** — groups customers by number of purchases:

```dax
Purchase Type =
VAR TxnCount =
    CALCULATE(
        COUNT(fact_sales[transaction_id]),
        ALLEXCEPT(fact_sales, fact_sales[customer_id])
    )
RETURN
SWITCH(
    TRUE(),
    TxnCount <= 5,  "Low (1–5)",
    TxnCount <= 10, "Medium (6–10)",
    "High (>10)"
)
```

**Discount Range** — groups transactions into discount bands:

```dax
Discount Range =
SWITCH(
    TRUE(),
    fact_sales[discount] <= 0,  "0%",
    fact_sales[discount] <= 5,  "1–5%",
    fact_sales[discount] <= 10, "6–10%",
    fact_sales[discount] <= 15, "11–15%",
    fact_sales[discount] <= 20, "16–20%",
    fact_sales[discount] <= 30, "21–30%",
    "Above 30%"
)
```

---

## Key Design Decisions & Honest Limitations

- **Data quality gaps ("Uncategorized" products, "Unknown" store types, missing cities) are reported openly in the dashboard's own insights**, not cleaned away artificially — an accurate picture of imperfect source data was prioritized over a cosmetically cleaner but less honest one.
- **Discount-null rows were imputed as 0%, a judgment call.** Because roughly 25% of rows had missing discounts, the "0%" discount group mixes true no-discount sales with rows where the discount was not recorded. A different, equally defensible choice would be to exclude them entirely.
- **The discount chart shows revenue by discount level, not cause and effect.** It does not show whether a discount increased sales compared with no discount, so it should not be read as proof that discounting works or fails.
- **Conversion Speed labels describe historical behavior.** "Fast" and "Slow" Converters are defined by the 90-day rule above, so they do not mean "new" and "old" customers.
- **Purchase Type cutoffs (5 and 10 purchases) are a simple, easy-to-explain choice,** not the only option. A distribution-based approach (for example percentiles) could shift customers between groups.
- **RFM segment thresholds (quartile-based) are a standard, but not the only, segmentation approach** — different quartile cutoffs or a five-tier model would shift specific customers between segments.
- **RFM segmentation and CLV exist in SQL but not yet in the dashboard** — see the "SQL-Only Insights" section above.
- **The data is synthetic**, so patterns may be cleaner than real retail data.

---

## Tech Stack

`PostgreSQL` (CTEs, window functions, RFM segmentation) · `Power BI` (dashboard, DAX measures, geographic mapping)

---

## Author

**Pooja Dhamale** </br>
Artificial Intelligence and Data Science
