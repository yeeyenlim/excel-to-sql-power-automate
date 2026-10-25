# Excel to SQL Load Automation (Power Automate Desktop)

A Power Automate Desktop flow that reads an Excel workbook from SharePoint and reloads a SQL Server table, replacing a manual SQL update. The load goes through a staging table and a stored procedure, so a bad file cannot leave the target table empty or half-loaded.

All table, column and file names in this repo are fictional sample data.

## How it works

1. Open the workbook from SharePoint in Excel (read-only).
2. Read all values from the worksheet, using the first row as column names.
3. Close Excel without saving.
4. Stop and alert if the sheet returned zero rows.
5. Open the SQL Server connection.
6. Clear the staging table `dbo.Stg_SalesOrders`.
7. Loop over each Excel row and insert it into staging as plain text, with single quotes escaped.
8. Run `dbo.usp_Load_SalesOrders`, which does the rest inside SQL (see below).
9. On any error, send an email with the error message, close the connection, and fail the run.
10. Close the SQL connection.

### What the stored procedure does

- Rejects the load if staging is empty.
- Rejects the load if any numeric value (`Quantity`, `UnitPrice`, `Discount`, `Tax`, `Total`) cannot be converted.
- Inside one transaction, deletes the rows in `dbo.SalesOrders` and inserts the converted staging rows.
- Writes a row to `dbo.LoadLog` for every run, successful or failed.
- Rolls back on any error, so the target table keeps its previous data.

## Sample schema

| Column | Type |
|---|---|
| `OrderId` | text |
| `Region` | text |
| `Product` | text |
| `Quantity` | integer |
| `UnitPrice` | decimal |
| `Discount` | decimal |
| `Tax` | decimal |
| `Total` | decimal |
| `Notes` | text |

The full DDL and the procedure are in [`load_proc.sql`](load_proc.sql).

## Requirements

- Power Automate Desktop
- Microsoft Excel installed on the machine running the flow
- Access to the SharePoint workbook
- A SQL Server login with `INSERT` and `DELETE` rights on the target and staging tables, and `EXECUTE` on the procedure

## Setup

1. Run `load_proc.sql` against your database, after renaming the objects to suit.
2. Build the flow following the steps above.
3. Provide the SQL connection through an input variable or Windows authentication. Never hardcode credentials in the flow or in this repo.
4. Never commit an exported flow file, because it contains the connection details.

## Known limitations

- **Full reload.** The target is replaced on every run, not merged. Rows added to the table by other processes are removed.
- **Row-by-row staging inserts.** Fine for small files. Batched inserts or bulk copy scale better.
- **Single worksheet.** The flow reads one sheet only.
- **Scheduling.** Running unattended on a schedule needs the right Power Automate licensing and a machine that stays available.

## Possible improvements

- Replace the full reload with a `MERGE` so unchanged rows are not rewritten.
- Store credentials in a secure vault.
- Alert on a row count that deviates sharply from the previous run.

