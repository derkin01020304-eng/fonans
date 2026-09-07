CREATE TABLE accounts (
 id TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL,
 currency TEXT NOT NULL DEFAULT 'RUB', openingMinor INTEGER NOT NULL DEFAULT 0,
 reservedMinor INTEGER NOT NULL DEFAULT 0 CHECK(reservedMinor >= 0),
 bankId TEXT, externalId TEXT, UNIQUE(bankId,externalId)
);
CREATE TABLE categories (id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, parentId TEXT REFERENCES categories(id));
CREATE TABLE transactions (
 id TEXT PRIMARY KEY, kind TEXT NOT NULL CHECK(kind IN ('income','expense','transfer','debtIn','debtOut','creditIn','creditOut')),
 amountMinor INTEGER NOT NULL CHECK(amountMinor > 0),
 accountId TEXT NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
 toAccountId TEXT REFERENCES accounts(id) ON DELETE RESTRICT, date TEXT NOT NULL,
 currency TEXT NOT NULL, category TEXT NOT NULL, subcategory TEXT NOT NULL DEFAULT '',
 comment TEXT NOT NULL DEFAULT '', merchant TEXT NOT NULL DEFAULT '', source TEXT NOT NULL DEFAULT '',
 paymentMethod TEXT NOT NULL DEFAULT '', workMinutes INTEGER NOT NULL DEFAULT 0 CHECK(workMinutes >= 0),
 mcc TEXT, externalKey TEXT UNIQUE, needsReview INTEGER NOT NULL DEFAULT 0 CHECK(needsReview IN (0,1)),
 linkType TEXT, linkId TEXT,
 CHECK((kind = 'transfer' AND toAccountId IS NOT NULL AND accountId <> toAccountId) OR (kind <> 'transfer' AND toAccountId IS NULL))
);
CREATE INDEX transactions_date ON transactions(date);
CREATE INDEX transactions_account ON transactions(accountId);
CREATE TABLE debts (
 id TEXT PRIMARY KEY, name TEXT NOT NULL, direction TEXT NOT NULL CHECK(direction IN ('iOwe','owedToMe')),
 initialMinor INTEGER NOT NULL CHECK(initialMinor > 0), remainingMinor INTEGER NOT NULL CHECK(remainingMinor BETWEEN 0 AND initialMinor),
 created TEXT NOT NULL, due TEXT NOT NULL, currency TEXT NOT NULL, comment TEXT NOT NULL DEFAULT ''
);
CREATE TABLE debt_payments (
 id TEXT PRIMARY KEY, parentId TEXT NOT NULL REFERENCES debts(id) ON DELETE RESTRICT,
 amountMinor INTEGER NOT NULL CHECK(amountMinor > 0), date TEXT NOT NULL,
 transactionId TEXT NOT NULL UNIQUE REFERENCES transactions(id) ON DELETE RESTRICT
);
CREATE TABLE credits (
 id TEXT PRIMARY KEY, name TEXT NOT NULL, bank TEXT NOT NULL, currency TEXT NOT NULL,
 initialMinor INTEGER NOT NULL CHECK(initialMinor > 0), remainingMinor INTEGER NOT NULL CHECK(remainingMinor BETWEEN 0 AND initialMinor),
 annualRateBps INTEGER NOT NULL CHECK(annualRateBps >= 0), monthlyMinor INTEGER NOT NULL CHECK(monthlyMinor > 0),
 start TEXT NOT NULL, end TEXT NOT NULL, nextPayment TEXT NOT NULL,
 paidInterestMinor INTEGER NOT NULL DEFAULT 0 CHECK(paidInterestMinor >= 0), comment TEXT NOT NULL DEFAULT ''
);
CREATE TABLE credit_payments (
 id TEXT PRIMARY KEY, parentId TEXT NOT NULL REFERENCES credits(id) ON DELETE RESTRICT,
 principalMinor INTEGER NOT NULL CHECK(principalMinor >= 0), interestMinor INTEGER NOT NULL CHECK(interestMinor >= 0),
 date TEXT NOT NULL, early INTEGER NOT NULL DEFAULT 0, transactionId TEXT REFERENCES transactions(id) ON DELETE RESTRICT
);
CREATE TABLE goals (
 id TEXT PRIMARY KEY, name TEXT NOT NULL, targetMinor INTEGER NOT NULL CHECK(targetMinor > 0),
 created TEXT NOT NULL, due TEXT NOT NULL, currency TEXT NOT NULL
);
CREATE TABLE savings (
 id TEXT PRIMARY KEY, amountMinor INTEGER NOT NULL CHECK(amountMinor <> 0),
 date TEXT NOT NULL, currency TEXT NOT NULL,
 transactionId TEXT NOT NULL UNIQUE REFERENCES transactions(id) ON DELETE RESTRICT,
 goalId TEXT REFERENCES goals(id) ON DELETE SET NULL
);
CREATE TABLE recurring_payments (
 id TEXT PRIMARY KEY, name TEXT NOT NULL, amountMinor INTEGER NOT NULL CHECK(amountMinor > 0),
 due TEXT NOT NULL, currency TEXT NOT NULL, frequency TEXT NOT NULL CHECK(frequency IN ('once','weekly','monthly','yearly')),
 reservedMinor INTEGER NOT NULL DEFAULT 0 CHECK(reservedMinor BETWEEN 0 AND amountMinor),
 accountId TEXT NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
 category TEXT NOT NULL DEFAULT 'Обязательные платежи', anchorDay INTEGER NOT NULL DEFAULT 1 CHECK(anchorDay BETWEEN 1 AND 31)
);
CREATE TABLE bank_connections (
 id TEXT PRIMARY KEY, provider TEXT NOT NULL, lastSync TEXT, cursor TEXT, status TEXT NOT NULL DEFAULT 'connected'
);
CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
