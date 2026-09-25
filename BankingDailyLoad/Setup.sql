USE [GOC_DataEngineer_Practice];
GO
IF SCHEMA_ID('bankdemo') IS NULL EXEC('CREATE SCHEMA bankdemo');
GO
IF OBJECT_ID('bankdemo.LoadedFiles') IS NULL
CREATE TABLE bankdemo.LoadedFiles(FileId int IDENTITY PRIMARY KEY, FilePath nvarchar(450) NOT NULL UNIQUE, ContentHash varbinary(32) NOT NULL, BusinessDate date NOT NULL, [RowCount] int NOT NULL, LoadedAt datetime2 NOT NULL DEFAULT SYSUTCDATETIME());
IF OBJECT_ID('bankdemo.Staging') IS NULL
CREATE TABLE bankdemo.Staging(StageId bigint IDENTITY PRIMARY KEY, FileId int NOT NULL REFERENCES bankdemo.LoadedFiles(FileId), TransactionId nvarchar(100), CustomerId nvarchar(100), CustomerName nvarchar(200), IsActive nvarchar(20), BirthDate nvarchar(50), OpenDate nvarchar(50), TransactionDate nvarchar(50), Amount nvarchar(100), TransactionType nvarchar(50), ValidationError nvarchar(500));
IF OBJECT_ID('bankdemo.Customers') IS NULL
CREATE TABLE bankdemo.Customers(CustomerId nvarchar(100) PRIMARY KEY, CustomerName nvarchar(200) NOT NULL, BirthDate date NOT NULL, OpenDate date NOT NULL, IsActive bit NOT NULL CHECK(IsActive=1));
IF OBJECT_ID('bankdemo.Transactions') IS NULL
CREATE TABLE bankdemo.Transactions(TransactionId nvarchar(100) PRIMARY KEY, CustomerId nvarchar(100) NOT NULL REFERENCES bankdemo.Customers(CustomerId), TransactionDate datetime2(0) NOT NULL, Amount decimal(18,2) NOT NULL, TransactionType nvarchar(50) NOT NULL, SourceStageId bigint NOT NULL REFERENCES bankdemo.Staging(StageId));
GO
CREATE OR ALTER PROCEDURE bankdemo.StageFile @FilePath nvarchar(450)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 DECLARE @name nvarchar(450)=RIGHT(@FilePath,CHARINDEX('\',REVERSE(@FilePath)+'\')-1);
 DECLARE @date date=TRY_CONVERT(date,SUBSTRING(@name,6,8),112);
 IF @name NOT LIKE 'bank[_]________[_]%.csv' OR @date IS NULL THROW 50001,'Expected bank_YYYYMMDD_partition.csv.',1;
 DECLARE @sql nvarchar(max), @hash varbinary(32), @lock int;
 SET @sql=N'SELECT @h=HASHBYTES(''SHA2_256'',BulkColumn) FROM OPENROWSET(BULK '''+REPLACE(@FilePath,'''','''''')+''', SINGLE_BLOB) x';
 EXEC sys.sp_executesql @sql,N'@h varbinary(32) OUTPUT',@h=@hash OUTPUT;
 BEGIN TRY
 BEGIN TRAN;
 EXEC @lock=sys.sp_getapplock @Resource='bankdemo.Load',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=30000;
 IF @lock<0 THROW 50002,'Could not acquire banking load lock.',1;
 IF EXISTS(SELECT 1 FROM bankdemo.LoadedFiles WHERE FilePath=@FilePath)
 BEGIN
  IF EXISTS(SELECT 1 FROM bankdemo.LoadedFiles WHERE FilePath=@FilePath AND ContentHash<>@hash) THROW 50003,'Previously loaded file was changed. Supply a new dated correction file.',1;
  COMMIT; RETURN;
 END;
 CREATE TABLE #Raw(TransactionId nvarchar(100),CustomerId nvarchar(100),CustomerName nvarchar(200),IsActive nvarchar(20),BirthDate nvarchar(50),OpenDate nvarchar(50),TransactionDate nvarchar(50),Amount nvarchar(100),TransactionType nvarchar(50));
 SET @sql=N'BULK INSERT #Raw FROM '''+REPLACE(@FilePath,'''','''''')+''' WITH(FORMAT=''CSV'',FIRSTROW=2,CODEPAGE=''65001'',FIELDQUOTE=''"'',ROWTERMINATOR=''0x0a'',MAXERRORS=0);';
 EXEC sys.sp_executesql @sql;
 INSERT bankdemo.LoadedFiles(FilePath,ContentHash,BusinessDate,[RowCount]) SELECT @FilePath,@hash,@date,COUNT(*) FROM #Raw;
 DECLARE @id int=CONVERT(int,SCOPE_IDENTITY());
 INSERT bankdemo.Staging(FileId,TransactionId,CustomerId,CustomerName,IsActive,BirthDate,OpenDate,TransactionDate,Amount,TransactionType,ValidationError)
 SELECT @id,TransactionId,CustomerId,CustomerName,IsActive,BirthDate,OpenDate,TransactionDate,Amount,TransactionType,
 NULLIF(CONCAT(
 CASE WHEN NULLIF(TRIM(TransactionId),'') IS NULL OR NULLIF(TRIM(CustomerId),'') IS NULL OR NULLIF(TRIM(CustomerName),'') IS NULL THEN 'Missing identifier or name; ' END,
 CASE WHEN IsActive IS NULL OR IsActive NOT IN('0','1') THEN 'IsActive must be 0 or 1; ' END,
 CASE WHEN TRY_CONVERT(date,BirthDate,103) IS NULL THEN 'Invalid birth date; ' END,
 CASE WHEN TRY_CONVERT(date,OpenDate,103) IS NULL THEN 'Invalid open date; ' END,
 CASE WHEN TRY_CONVERT(datetime2(0),TransactionDate,103) IS NULL THEN 'Invalid transaction date; ' END,
 CASE WHEN TRY_CONVERT(decimal(18,2),Amount) IS NULL OR TRY_CONVERT(decimal(18,2),Amount)<=0 THEN 'Invalid positive amount; ' END,
 CASE WHEN TransactionType IS NULL OR TransactionType NOT IN('DEPOSIT','WITHDRAWAL','TRANSFER') THEN 'Invalid transaction type; ' END),'')
 FROM #Raw;
 COMMIT;
 END TRY
 BEGIN CATCH
 IF @@TRANCOUNT>0 ROLLBACK;
 THROW;
 END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE bankdemo.PublishActive
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRAN;
 DECLARE @lock int;
 EXEC @lock=sys.sp_getapplock @Resource='bankdemo.Load',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=30000;
 IF @lock<0 THROW 50004,'Could not acquire publish lock.',1;
 -- Rebuild only the small demonstration targets, atomically, from durable staging.
 DELETE bankdemo.Transactions;
 DELETE bankdemo.Customers;
 ;WITH latest AS(
 SELECT s.*,ROW_NUMBER() OVER(PARTITION BY CustomerId ORDER BY f.BusinessDate DESC, s.StageId DESC) rn
 FROM bankdemo.Staging s JOIN bankdemo.LoadedFiles f ON f.FileId=s.FileId
 WHERE NULLIF(TRIM(CustomerId),'') IS NOT NULL)
 INSERT bankdemo.Customers(CustomerId,CustomerName,BirthDate,OpenDate,IsActive)
 SELECT CustomerId,CustomerName,TRY_CONVERT(date,BirthDate,103),TRY_CONVERT(date,OpenDate,103),1 FROM latest
 WHERE rn=1 AND IsActive='1' AND NULLIF(TRIM(CustomerName),'') IS NOT NULL AND TRY_CONVERT(date,BirthDate,103) IS NOT NULL AND TRY_CONVERT(date,OpenDate,103) IS NOT NULL;
 ;WITH latest AS(
 SELECT s.*,ROW_NUMBER() OVER(PARTITION BY TransactionId ORDER BY f.BusinessDate DESC,s.StageId DESC) rn
 FROM bankdemo.Staging s JOIN bankdemo.LoadedFiles f ON f.FileId=s.FileId)
 INSERT bankdemo.Transactions(TransactionId,CustomerId,TransactionDate,Amount,TransactionType,SourceStageId)
 SELECT s.TransactionId,s.CustomerId,CONVERT(datetime2(0),s.TransactionDate,103),CONVERT(decimal(18,2),s.Amount),s.TransactionType,s.StageId
 FROM latest s JOIN bankdemo.Customers c ON c.CustomerId=s.CustomerId
 WHERE s.rn=1 AND s.IsActive='1' AND s.ValidationError IS NULL;
 COMMIT;
 END TRY
 BEGIN CATCH
 IF @@TRANCOUNT>0 ROLLBACK;
 THROW;
 END CATCH;
END;
GO
