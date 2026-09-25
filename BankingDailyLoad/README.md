# Banking daily CSV load

Target: `.\SQLEXPRESS`, database `GOC_DataEngineer_Practice`, Windows authentication.
All data is fictional. Existing dbo tables are untouched.

## Run the load

Double-click `Run.cmd`, or run it from a terminal to keep the results visible.
Put new daily files in `input`, using names such as `bank_20260926_01.csv` through `bank_20260926_06.csv`. Any number of matching files is supported. Keep the same column order and header as the supplied files, UTF-8 encoding, LF line endings, and standard CSV double-quote escaping. Files must be completely written before starting the package. The SQL Server service account must be able to read them, since SQL Server reads the CSV contents.

The package scans `bank_*.csv` without recursing into subfolders. Previously loaded paths with identical contents are skipped. Changing an already loaded file produces an error; use a new dated correction file. File paths longer than 450 characters are unsupported. If moving the package, change its `User::InputFolder` variable in SSIS, or rebuild it with `Build-Package.ps1` using Windows PowerShell 5.1. Connection and folder values currently point to this laptop.

## Package design

`BankingDailyLoad.dtsx` is a SQL Server 2019 SSIS package with a native Foreach File container and Execute SQL tasks:

1. Enumerate the daily CSV files.
2. Call `bankdemo.StageFile` for each file. SQL Server BULK INSERT reads the CSV, preserves source values as text in staging, validates values, and records the file's SHA-256 hash.
3. After all files succeed, call `bankdemo.PublishActive` to convert dates and amounts and publish the active records.

This implementation uses SQL-based CSV ingestion and conversion controlled by SSIS. It does not use a Flat File Source, Data Conversion, or Conditional Split data-flow component. The transformations are visible in `Setup.sql`.

The file schema combines customer details and a transaction in each row:

`TransactionId,CustomerId,CustomerName,IsActive,BirthDate,OpenDate,TransactionDate,Amount,TransactionType`

Dates are `dd/MM/yyyy`; transaction timestamps are `dd/MM/yyyy HH:mm:ss`. SQL conversion style 103 is explicit. Amounts use a decimal point, must be positive, and become `decimal(18,2)`. Transaction types are DEPOSIT, WITHDRAWAL, or TRANSFER. IsActive is 1 or 0.

## Tables and behavior

| Table | Purpose |
|---|---|
| bankdemo.Staging | Every successfully parsed source row, active and inactive, with raw dates and validation errors |
| bankdemo.Customers | Latest active customers, with typed birth and account-open dates |
| bankdemo.Transactions | Valid transactions from active source rows whose customers are currently active |
| bankdemo.LoadedFiles | File path, content hash, business date, source row count, and UTC load time |

The business date comes from the filename. Latest customer and transaction versions are selected by business date, then staging arrival order on ties. Avoid conflicting versions of the same customer within one daily delivery. Later inactive customer records remove that customer's rows from the active-only targets; their history remains in staging. Invalid latest customer details suppress that customer from the target. A transaction-only error does not prevent valid customer details from loading.

For this small practice exercise, final tables are rebuilt inside one transaction from retained staging. This is deliberately simple; it is not a large-volume incremental warehouse design. Earlier successfully staged files survive a later file failure, but final publishing does not run until all files succeed. Retry after correcting the unprocessed file. Structural CSV errors fail the file; ordinary value errors are retained with `ValidationError`. No files are deleted or moved.

## Inspect in SQL Server Management Studio

Refresh Tables under `GOC_DataEngineer_Practice` and look for the `bankdemo` schema. Open `Verify.sql` to view counts, active targets, inactive rows, and rejected rows.

Initial sample and identical rerun results:

| Measure | Count |
|---|---:|
| Loaded files | 6 |
| Staged rows | 36 |
| Inactive staged rows | 12 |
| Rejected active transaction rows | 2 |
| Active customers | 12 |
| Active valid transactions | 22 |

TX0001 deliberately contains 31 February; TX0003 contains BAD_AMOUNT. Both remain in staging with clear errors.

## Setup and editing

The tables and procedures have already been installed and the package has run successfully on this laptop. `Setup.sql` is included for review or recreation; it adds missing practice tables and updates these two practice procedures without touching existing dbo tables.

To edit visually, open `BankingDailyLoad.sln` in Visual Studio 2019 and double-click `BankingDailyLoad.dtsx` under SSIS Packages. The project targets SQL Server 2019. Build Solution produces `bin\Development\BankingDailyLoad.ispac`. `Build-Package.ps1` is its reproducible builder and requires the installed SQL Server 2019 ManagedDTS assemblies and Windows PowerShell 5.1.

No unattended daily schedule has been created. `Run.cmd` is the entry point for a future Windows Task Scheduler job, running as a Windows account that can access the database and files. Keep all six files ready before running each delivery.

## Current laptop input folder

The saved package deliberately continues to use the original loaded input folder: `C:\Users\kalya\Documents\Codex\2026-09-25\ca\outputs\BankingDailyLoad\input`. This preserves file-path identity for repeat loads in the existing database. The repository includes copies of all six samples. On another laptop or a fresh database, rebuild the package with `Build-Package.ps1` to use the input folder next to the project; configure the SQL connection before running. Do not switch to copied input paths against this existing database without reconciling LoadedFiles, since file-path identity would treat those copies as new deliveries.
