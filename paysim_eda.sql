
-- Project: PaySim Fraud Detection
-- File: paysim_eda.sql
-- Purpose: Schema setup, data load, and exploratory analysis
-- Author: Manzoor Syiemlieh

CREATE DATABASE IF NOT EXISTS paysim_db;
USE paysim_db;

CREATE TABLE transactions (
    step            INT,
    type            VARCHAR(10),
    amount          DECIMAL(15,2),
    nameOrig        VARCHAR(20),
    oldbalanceOrg   DECIMAL(15,2),
    newbalanceOrig  DECIMAL(15,2),
    nameDest        VARCHAR(20),
    oldbalanceDest  DECIMAL(15,2),
    newbalanceDest  DECIMAL(15,2),
    isFraud         TINYINT,
    isFlaggedFraud  TINYINT
);

USE paysim_db;

-- NOTE: change the file path below to wherever the PaySim CSV sits on your machine.

-- Load the CSV into the transactions table.
LOAD DATA LOCAL INFILE 'C:/Users/Admin/Desktop/PaySim_Fraud_Detection/PaySim_Data/paysim dataset.csv'
INTO TABLE transactions
FIELDS TERMINATED BY ','
LINES TERMINATED BY '\n'
IGNORE 1 LINES;


-- Load data verification: expect 6,362,620 rows and 8,213 frauds
SELECT COUNT(*) FROM transactions;       
SELECT SUM(isFraud) FROM transactions;   
SELECT type, COUNT(*) FROM transactions GROUP BY type;


-- Index on nameOrig — speeds up the self-join in query 1.5
CREATE INDEX idx_nameOrig ON transactions (nameOrig);


-- 1.1 Fraud rate by transaction type
SELECT
    type,
    COUNT(*) AS total_txns,
    SUM(isFraud) AS fraud_txns,
    ROUND(100.0 * SUM(isFraud) / COUNT(*), 4) AS fraud_rate_pct
FROM transactions
GROUP BY type
ORDER BY fraud_rate_pct DESC;
-- Finding: fraud occurs ONLY in TRANSFER (0.77%) and CASH_OUT (0.18%); zero in PAYMENT, DEBIT, CASH_IN.


-- 1.2 Built-in rule effectiveness (caught vs missed)
SELECT
    SUM(isFraud) AS total_frauds,
    SUM(isFlaggedFraud) AS total_flagged,
    SUM(CASE WHEN isFraud = 1 AND isFlaggedFraud = 1 THEN 1 ELSE 0 END) AS frauds_caught_by_rule,
    SUM(CASE WHEN isFraud = 1 AND isFlaggedFraud = 0 THEN 1 ELSE 0 END) AS frauds_missed_by_rule
FROM transactions;
-- Finding: built-in rule caught 16 of 8,213 frauds = 0.19% recall (precise but nearly blind). Baseline to beat.


-- 1.3 Balance-draining signal (fraud vs legit)
SELECT
    isFraud,
    COUNT(*) AS txns,
    SUM(CASE WHEN oldbalanceOrg > 0 AND newbalanceOrig = 0 THEN 1 ELSE 0 END) AS drained_count,
    ROUND(100.0 * SUM(CASE WHEN oldbalanceOrg > 0 AND newbalanceOrig = 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS drained_pct
FROM transactions
WHERE type IN ('TRANSFER', 'CASH_OUT')
GROUP BY isFraud;
-- Finding: 97.6% of frauds drain the origin vs 42.7% of legit — strong but not decisive (legit cash-outs also empty accounts).


-- 1.4 Destination-balance anomaly (money moved but receiver balance stayed zero)
SELECT
    isFraud,
    COUNT(*) AS txns,
    SUM(CASE WHEN oldbalanceDest = 0 AND newbalanceDest = 0 AND amount > 0 THEN 1 ELSE 0 END) AS dest_zero_count,
    ROUND(100.0 * SUM(CASE WHEN oldbalanceDest = 0 AND newbalanceDest = 0 AND amount > 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS dest_zero_pct
FROM transactions
WHERE type IN ('TRANSFER', 'CASH_OUT')
GROUP BY isFraud;
-- Finding: 49.6% of frauds leave the destination balance at zero vs 0.06% of legit (~800x) — the cleanest single signal.


-- 1.5 Mule chain: do fraudulent-transfer destinations later cash out.
SELECT
    COUNT(DISTINCT t.nameDest) AS fraud_transfer_destinations,
    COUNT(DISTINCT c.nameOrig) AS destinations_that_cashed_out
FROM transactions t
LEFT JOIN transactions c
       ON c.nameOrig = t.nameDest
      AND c.type = 'CASH_OUT'
WHERE t.type = 'TRANSFER'
  AND t.isFraud = 1;
-- Finding: only 3 of 4,097 fraud-transfer destinations ever cash out — the mule chain is NOT traceable here, so no chaining feature is built.


-- 1.6 Fraud concentration by transaction size (10 amount bands)
WITH banded AS (
    SELECT
        amount,
        isFraud,
        NTILE(10) OVER (ORDER BY amount) AS amount_decile
    FROM transactions
    WHERE type IN ('TRANSFER', 'CASH_OUT')
)
SELECT
    amount_decile,
    COUNT(*) AS txns,
    MIN(amount) AS min_amount,
    MAX(amount) AS max_amount,
    SUM(isFraud) AS frauds,
    ROUND(100.0 * SUM(isFraud) / COUNT(*), 3) AS fraud_rate_pct
FROM banded
GROUP BY amount_decile
ORDER BY amount_decile;
-- Finding: fraud concentrates in the largest transactions — top decile holds 3,724 frauds (45%) at 1.34%; non-linear (U-shaped).