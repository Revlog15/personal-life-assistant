#!/usr/bin/env python3
"""Generate an anonymous v1_initial_mvp SQLite fixture matching PLAData v1.0.0 schema (PRD §11.5)."""
import sqlite3
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "Packages" / "PLAData" / "Tests" / "PLADataTests" / "Fixtures" / "pla_v1_initial_mvp.sqlite"
OUT.parent.mkdir(parents=True, exist_ok=True)
if OUT.exists():
    OUT.unlink()

conn = sqlite3.connect(str(OUT))
cur = conn.cursor()
cur.execute("PRAGMA foreign_keys = ON;")

# GRDB DatabaseMigrator table
cur.execute('CREATE TABLE "grdb_migrations" ("identifier" TEXT NOT NULL PRIMARY KEY);')
cur.execute('INSERT INTO "grdb_migrations" ("identifier") VALUES (?);', ("v1_initial_mvp",))

# Exact v1_initial_mvp DDL matching DatabaseManager.swift
cur.executescript(
    """
    CREATE TABLE "app_metadata" (
        "key" TEXT PRIMARY KEY,
        "value" TEXT NOT NULL
    );

    CREATE TABLE "categories" (
        "id" TEXT PRIMARY KEY,
        "name" TEXT NOT NULL,
        "scope" INTEGER NOT NULL,
        "iconName" TEXT NOT NULL,
        "colorToken" TEXT NOT NULL,
        "isSystem" BOOLEAN NOT NULL DEFAULT 0,
        "isArchived" BOOLEAN NOT NULL DEFAULT 0,
        "sortOrder" INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE "recurrence_rules" (
        "id" TEXT PRIMARY KEY,
        "frequency" INTEGER NOT NULL,
        "interval" INTEGER NOT NULL DEFAULT 1,
        "weekdaysMask" INTEGER,
        "anchorDayOfMonth" INTEGER,
        "anchorMonth" INTEGER,
        "endDateLocal" TEXT,
        "maxOccurrences" INTEGER
    );

    CREATE TABLE "accounts" (
        "id" TEXT PRIMARY KEY,
        "name" TEXT NOT NULL,
        "type" INTEGER NOT NULL,
        "initialBalance" INTEGER NOT NULL DEFAULT 0,
        "iconName" TEXT NOT NULL,
        "colorToken" TEXT NOT NULL,
        "isDefault" BOOLEAN NOT NULL DEFAULT 0,
        "isArchived" BOOLEAN NOT NULL DEFAULT 0,
        "sortOrder" INTEGER NOT NULL DEFAULT 0,
        "createdAt" DOUBLE NOT NULL
    );

    CREATE TABLE "tasks" (
        "id" TEXT PRIMARY KEY,
        "title" TEXT NOT NULL,
        "notes" TEXT,
        "dueDateLocal" TEXT,
        "dueTimeMinutes" INTEGER,
        "priority" INTEGER NOT NULL DEFAULT 1,
        "status" INTEGER NOT NULL DEFAULT 0,
        "categoryId" TEXT REFERENCES "categories"("id") ON DELETE SET NULL,
        "recurrenceRuleId" TEXT REFERENCES "recurrence_rules"("id") ON DELETE SET NULL,
        "completedAt" DOUBLE,
        "createdAt" DOUBLE NOT NULL,
        "updatedAt" DOUBLE NOT NULL
    );

    CREATE TABLE "bills" (
        "id" TEXT PRIMARY KEY,
        "name" TEXT NOT NULL,
        "amount" INTEGER NOT NULL,
        "isVariableAmount" BOOLEAN NOT NULL DEFAULT 0,
        "nextDueDateLocal" TEXT NOT NULL,
        "recurrenceRuleId" TEXT NOT NULL REFERENCES "recurrence_rules"("id") ON DELETE RESTRICT,
        "defaultAccountId" TEXT NOT NULL REFERENCES "accounts"("id") ON DELETE RESTRICT,
        "categoryId" TEXT NOT NULL REFERENCES "categories"("id") ON DELETE RESTRICT,
        "isActive" BOOLEAN NOT NULL DEFAULT 1,
        "lastPaidDateLocal" TEXT,
        "createdAt" DOUBLE NOT NULL,
        "updatedAt" DOUBLE NOT NULL
    );

    CREATE TABLE "reminders" (
        "id" TEXT PRIMARY KEY,
        "ownerType" INTEGER NOT NULL,
        "ownerId" TEXT NOT NULL,
        "triggerType" INTEGER NOT NULL DEFAULT 0,
        "offsetMinutes" INTEGER,
        "fireDateLocal" TEXT NOT NULL,
        "soundName" TEXT NOT NULL,
        "isEnabled" BOOLEAN NOT NULL DEFAULT 1,
        "lastScheduledAt" DOUBLE
    );

    CREATE TABLE "transactions" (
        "id" TEXT PRIMARY KEY,
        "type" INTEGER NOT NULL,
        "amount" INTEGER NOT NULL,
        "accountId" TEXT NOT NULL REFERENCES "accounts"("id") ON DELETE RESTRICT,
        "destinationAccountId" TEXT REFERENCES "accounts"("id") ON DELETE RESTRICT,
        "categoryId" TEXT REFERENCES "categories"("id") ON DELETE RESTRICT,
        "billId" TEXT REFERENCES "bills"("id") ON DELETE SET NULL,
        "dateLocal" TEXT NOT NULL,
        "note" TEXT,
        "createdAt" DOUBLE NOT NULL,
        "updatedAt" DOUBLE NOT NULL
    );

    CREATE TABLE "budgets" (
        "id" TEXT PRIMARY KEY,
        "categoryId" TEXT REFERENCES "categories"("id") ON DELETE SET NULL,
        "amount" INTEGER NOT NULL,
        "effectiveFromMonth" TEXT NOT NULL,
        "isActive" BOOLEAN NOT NULL DEFAULT 1,
        "createdAt" DOUBLE NOT NULL,
        "updatedAt" DOUBLE NOT NULL
    );

    CREATE TABLE "insights" (
        "id" TEXT PRIMARY KEY,
        "ruleCode" TEXT NOT NULL,
        "periodKey" TEXT NOT NULL,
        "subjectId" TEXT,
        "severity" INTEGER NOT NULL,
        "dismissedAt" DOUBLE,
        "feedback" INTEGER,
        "generatedAt" DOUBLE NOT NULL
    );

    CREATE INDEX "idx_tasks_status_due" ON "tasks"("status", "dueDateLocal");
    CREATE INDEX "idx_transactions_date_type" ON "transactions"("dateLocal", "type");
    CREATE INDEX "idx_transactions_account" ON "transactions"("accountId");
    CREATE INDEX "idx_transactions_dest_account" ON "transactions"("destinationAccountId");
    CREATE INDEX "idx_reminders_fire" ON "reminders"("isEnabled", "fireDateLocal");
    CREATE INDEX "idx_reminders_owner" ON "reminders"("ownerId");
    CREATE INDEX "idx_bills_active_due" ON "bills"("isActive", "nextDueDateLocal");
    CREATE UNIQUE INDEX "idx_insights_dedup" ON "insights"("ruleCode", "periodKey", "subjectId");
    """
)

ts = 1795600000.0
# Deterministic anonymous UUIDs
CAT_FOOD = "11111111-1111-4111-8111-111111111101"
CAT_BILL = "11111111-1111-4111-8111-111111111102"
CAT_SALARY = "11111111-1111-4111-8111-111111111103"
CAT_TASK = "11111111-1111-4111-8111-111111111104"

ACC_BCA = "22222222-2222-4222-8222-222222222201"
ACC_GOPAY = "22222222-2222-4222-8222-222222222202"

RULE_BILL = "33333333-3333-4333-8333-333333333301"
BILL_NET = "44444444-4444-4444-8444-444444444401"

TASK_1 = "55555555-5555-4555-8555-555555555501"
TASK_2 = "55555555-5555-4555-8555-555555555502"

REM_1 = "66666666-6666-4666-8666-666666666601"

TX_INC = "77777777-7777-4777-8777-777777777701"
TX_EXP = "77777777-7777-4777-8777-777777777702"
TX_TRF = "77777777-7777-4777-8777-777777777703"

BUDGET_TOTAL = "88888888-8888-4888-8888-888888888801"
INSIGHT_1 = "99999999-9999-4999-8999-999999999901"

cur.executemany(
    "INSERT INTO app_metadata (key, value) VALUES (?, ?);",
    [("schemaVersion", "1"), ("appVersion", "1.0.0")],
)

cur.executemany(
    "INSERT INTO categories (id, name, scope, iconName, colorToken, isSystem, isArchived, sortOrder) VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
    [
        (CAT_FOOD, "Makan & Minum", 0, "fork.knife", "orange", 1, 0, 1),
        (CAT_BILL, "Tagihan & Utilitas", 0, "bolt.fill", "teal", 1, 0, 2),
        (CAT_SALARY, "Gaji", 1, "banknote.fill", "green", 1, 0, 1),
        (CAT_TASK, "Kerja", 2, "briefcase.fill", "blue", 1, 0, 1),
    ],
)

cur.executemany(
    "INSERT INTO accounts (id, name, type, initialBalance, iconName, colorToken, isDefault, isArchived, sortOrder, createdAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
    [
        (ACC_BCA, "Bank Utama", 1, 2_000_000, "building.columns.fill", "blue", 1, 0, 1, ts),
        (ACC_GOPAY, "E-Wallet", 2, 500_000, "wallet.pass.fill", "teal", 0, 0, 2, ts),
    ],
)

cur.execute(
    "INSERT INTO recurrence_rules (id, frequency, interval, anchorDayOfMonth) VALUES (?, ?, ?, ?);",
    (RULE_BILL, 2, 1, 15),
)

cur.execute(
    "INSERT INTO bills (id, name, amount, isVariableAmount, nextDueDateLocal, recurrenceRuleId, defaultAccountId, categoryId, isActive, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
    (BILL_NET, "Internet Rumah", 350_000, 0, "2026-12-15", RULE_BILL, ACC_BCA, CAT_BILL, 1, ts, ts),
)

cur.executemany(
    "INSERT INTO tasks (id, title, notes, dueDateLocal, dueTimeMinutes, priority, status, categoryId, recurrenceRuleId, completedAt, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
    [
        (TASK_1, "Kirim laporan bulanan", "Fixture v1 aktif", "2026-12-01", 900, 2, 0, CAT_TASK, None, None, ts, ts),
        (TASK_2, "Selesai di v1", None, "2026-11-20", 600, 1, 1, CAT_TASK, None, ts, ts, ts),
    ],
)

cur.execute(
    "INSERT INTO reminders (id, ownerType, ownerId, triggerType, offsetMinutes, fireDateLocal, soundName, isEnabled, lastScheduledAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);",
    (REM_1, 0, TASK_1, 0, -1440, "2026-11-30T09:00", "pla_urgent.caf", 1, None),
)

# Expected balances after transactions:
# Bank Utama: 2,000,000 + 5,000,000 (income) - 500,000 (transfer out) = 6,500,000
# E-Wallet:     500,000 + 500,000 (transfer in) - 150,000 (expense)  =   850,000
# Total liquid wealth = 7,350,000
cur.executemany(
    "INSERT INTO transactions (id, type, amount, accountId, destinationAccountId, categoryId, billId, dateLocal, note, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
    [
        (TX_INC, 1, 5_000_000, ACC_BCA, None, CAT_SALARY, None, "2026-11-01", "Gaji bulanan", ts, ts),
        (TX_TRF, 2, 500_000, ACC_BCA, ACC_GOPAY, None, None, "2026-11-02", "Top up e-wallet", ts, ts),
        (TX_EXP, 0, 150_000, ACC_GOPAY, None, CAT_FOOD, None, "2026-11-05", "Makan siang", ts, ts),
    ],
)

cur.execute(
    "INSERT INTO budgets (id, categoryId, amount, effectiveFromMonth, isActive, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?, ?);",
    (BUDGET_TOTAL, None, 3_500_000, "2026-11", 1, ts, ts),
)

cur.execute(
    "INSERT INTO insights (id, ruleCode, periodKey, subjectId, severity, dismissedAt, feedback, generatedAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
    (INSIGHT_1, "R-FIN-05c", "2026-11", CAT_FOOD, 0, None, 1, ts),
)

conn.commit()
conn.close()
print(f"Generated static v1 SQLite fixture: {OUT} ({OUT.stat().st_size} bytes)")
