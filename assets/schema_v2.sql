CREATE TABLE category_rules (merchant TEXT PRIMARY KEY, category TEXT NOT NULL);
CREATE TABLE bank_snapshots (
 accountId TEXT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
 balanceMinor INTEGER NOT NULL, asOf TEXT NOT NULL
);
CREATE TABLE api_requests (
 id TEXT PRIMARY KEY, tool TEXT NOT NULL, payloadHash TEXT NOT NULL, result TEXT NOT NULL, created TEXT NOT NULL
);
CREATE TABLE audit_log (id TEXT PRIMARY KEY, action TEXT NOT NULL, created TEXT NOT NULL);
CREATE INDEX transactions_link ON transactions(linkType,linkId);

ALTER TABLE credits ADD COLUMN paymentDay INTEGER NOT NULL DEFAULT 1 CHECK(paymentDay BETWEEN 1 AND 31);
UPDATE credits SET paymentDay = CAST(strftime('%d',nextPayment) AS INTEGER);
