/* ------------------------------------------------------------------
   Sample schema: Excel -> SQL Server load using a staging table.
   All names are fictional. Rename them to match your own database.
   ------------------------------------------------------------------ */

-- 1. Target table (the table the reporting side reads from).
CREATE TABLE dbo.SalesOrders (
    OrderId   NVARCHAR(50)   NOT NULL,
    Region    NVARCHAR(50)   NULL,
    Product   NVARCHAR(100)  NULL,
    Quantity  INT            NULL,
    UnitPrice DECIMAL(18,2)  NULL,
    Discount  DECIMAL(18,2)  NULL,
    Tax       DECIMAL(18,2)  NULL,
    Total     DECIMAL(18,2)  NULL,
    Notes     NVARCHAR(500)  NULL
);
GO

-- 2. Staging table: everything is text, so the flow never converts types.
CREATE TABLE dbo.Stg_SalesOrders (
    OrderId   NVARCHAR(255) NULL,
    Region    NVARCHAR(255) NULL,
    Product   NVARCHAR(255) NULL,
    Quantity  NVARCHAR(255) NULL,
    UnitPrice NVARCHAR(255) NULL,
    Discount  NVARCHAR(255) NULL,
    Tax       NVARCHAR(255) NULL,
    Total     NVARCHAR(255) NULL,
    Notes     NVARCHAR(255) NULL
);
GO

-- 3. Run log: one row per run, success or failure.
CREATE TABLE dbo.LoadLog (
    LogId      INT IDENTITY(1,1) PRIMARY KEY,
    LoadTime   DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    RowsLoaded INT NULL,
    Status     VARCHAR(10) NOT NULL,
    Message    NVARCHAR(4000) NULL
);
GO

-- 4. Load procedure: validates, then replaces the target in ONE transaction.
--    If anything fails, the target table keeps its previous data.
CREATE OR ALTER PROCEDURE dbo.usp_Load_SalesOrders
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @staged INT, @bad INT, @loaded INT;

    BEGIN TRY
        SELECT @staged = COUNT(*) FROM dbo.Stg_SalesOrders;

        -- Guard 1: an empty or failed read must never wipe the target.
        IF @staged = 0
            THROW 50001, 'Staging table is empty. Target table not touched.', 1;

        -- Guard 2: reject the whole load if any numeric value is invalid.
        SELECT @bad = COUNT(*)
        FROM dbo.Stg_SalesOrders
        WHERE (NULLIF(LTRIM(RTRIM(Quantity)),  '') IS NOT NULL AND TRY_CONVERT(INT,           Quantity)  IS NULL)
           OR (NULLIF(LTRIM(RTRIM(UnitPrice)), '') IS NOT NULL AND TRY_CONVERT(DECIMAL(18,2), UnitPrice) IS NULL)
           OR (NULLIF(LTRIM(RTRIM(Discount)),  '') IS NOT NULL AND TRY_CONVERT(DECIMAL(18,2), Discount)  IS NULL)
           OR (NULLIF(LTRIM(RTRIM(Tax)),       '') IS NOT NULL AND TRY_CONVERT(DECIMAL(18,2), Tax)       IS NULL)
           OR (NULLIF(LTRIM(RTRIM(Total)),     '') IS NOT NULL AND TRY_CONVERT(DECIMAL(18,2), Total)     IS NULL);

        IF @bad > 0
            THROW 50002, 'Staging has rows with invalid numeric values. Target table not touched.', 1;

        BEGIN TRAN;

            DELETE FROM dbo.SalesOrders;

            INSERT INTO dbo.SalesOrders
                (OrderId, Region, Product, Quantity, UnitPrice, Discount, Tax, Total, Notes)
            SELECT OrderId,
                   Region,
                   Product,
                   TRY_CONVERT(INT,           NULLIF(LTRIM(RTRIM(Quantity)),  '')),
                   TRY_CONVERT(DECIMAL(18,2), NULLIF(LTRIM(RTRIM(UnitPrice)), '')),
                   TRY_CONVERT(DECIMAL(18,2), NULLIF(LTRIM(RTRIM(Discount)),  '')),
                   TRY_CONVERT(DECIMAL(18,2), NULLIF(LTRIM(RTRIM(Tax)),       '')),
                   TRY_CONVERT(DECIMAL(18,2), NULLIF(LTRIM(RTRIM(Total)),     '')),
                   Notes
            FROM dbo.Stg_SalesOrders;

            SET @loaded = @@ROWCOUNT;

            INSERT INTO dbo.LoadLog (RowsLoaded, Status, Message)
            VALUES (@loaded, 'OK', NULL);

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        INSERT INTO dbo.LoadLog (RowsLoaded, Status, Message)
        VALUES (NULL, 'FAILED', ERROR_MESSAGE());

        THROW;   -- re-raise so the Power Automate flow sees the failure
    END CATCH
END
GO
