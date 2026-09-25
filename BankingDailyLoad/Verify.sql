USE GOC_DataEngineer_Practice;
SELECT 'Files' AS Measure,COUNT(*) AS Total FROM bankdemo.LoadedFiles
UNION ALL SELECT 'Staged rows',COUNT(*) FROM bankdemo.Staging
UNION ALL SELECT 'Inactive staged rows',COUNT(*) FROM bankdemo.Staging WHERE IsActive='0'
UNION ALL SELECT 'Rejected rows',COUNT(*) FROM bankdemo.Staging WHERE ValidationError IS NOT NULL
UNION ALL SELECT 'Active customers',COUNT(*) FROM bankdemo.Customers
UNION ALL SELECT 'Active valid transactions',COUNT(*) FROM bankdemo.Transactions;
SELECT * FROM bankdemo.Customers ORDER BY CustomerId;
SELECT * FROM bankdemo.Transactions ORDER BY TransactionId;
SELECT * FROM bankdemo.Staging WHERE IsActive='0' OR ValidationError IS NOT NULL ORDER BY StageId;
