


/* I scream, you scream, we all scream for .... indexes?? */


USE StackOverflow2010;
GO 

EXEC CleanupJMRIndexes;

SET STATISTICS IO, TIME ON;



/* 
Let's look at the Users table and look up particular AccountIds 
This does 7,400 reads with a CI scan because there is no index on AccountId */

SELECT u.id, u.DisplayName, u.Reputation, u.CreationDate 
FROM dbo.Users AS u 
WHERE u.AccountId = 1; 


/*
Doing CI scans to look up a particular ID value is concerning
This is a column that looks like a FK to another table, 
	it is an INT, and there are very few indexes on the table,
	on the face of it this is a great candidate for indexing.
If we query against this all the time, it would be another good sign we should maybe index it.
*/


CREATE INDEX JMR_Dbo_Users_AccountId
ON dbo.Users (AccountId)
WITH (MAXDOP = 0); 

/*
After the index is added we do an index seek for a single row and a single key lookup.
Much better, that does 6 reads.
*/

SELECT u.id, u.DisplayName, u.Reputation, u.CreationDate 
FROM dbo.Users AS u 
WHERE u.AccountId = 1; 

/* Until proven otherwise, not having index on fields you could be seeking regularly into is a red flag */


/* Residual Predicates */

/* 
Whenever SQL has to do a key lookup to get data to filter based on a where clause,
	that is a red flag. 
These are called residual predicates and means you should 	probably add the Predicate 
	from the key lookup to the index key.
I'm using local variables here to purposefully get small estimates.
*/

DECLARE @Reputation INT = 2

SELECT u.id, u.DisplayName, u.LastAccessDate, u.CreationDate, u.Reputation, u.Views
FROM dbo.Users AS u
WHERE u.Reputation = @Reputation
	AND u.Views > 20
ORDER BY u.LastAccessDate DESC;
GO

/*
Rather than do Reputation = 2, let's try 1 instead.
Reputation = 1 is the default for a new user who has never done anything.
This did 122,000 reads. Reading the entire clustered index only does 7,400 reads.
*/

DECLARE @Reputation INT = 1

SELECT u.id, u.DisplayName, u.LastAccessDate, u.CreationDate, u.Reputation, u.Views
FROM dbo.Users AS u
WHERE u.Reputation = @Reputation
	AND u.Views > 20
ORDER BY u.LastAccessDate DESC;
GO

/* How do we fix it? 
Non-index solution- Use a literal instead of a variable that prevents 
	the optimizer from knowing what the data really has*/

SELECT u.id, u.DisplayName, u.LastAccessDate, u.CreationDate, u.Reputation, u.Views
FROM dbo.Users AS u
WHERE u.Reputation = 1
	AND u.Views > 20
ORDER BY u.LastAccessDate DESC;
	
/* What if we want it faster though?
Add make sure that residual key lookup is added to the index, 
	in this case we want to make it the second key */

CREATE INDEX JMR_IX_Dbo_Users_Reputation_Views
ON dbo.Users (Reputation, Views)
WITH (MAXDOP = 0); 



/* I'll run it with literals now so we have better estimates */

/* Now this only does 14 key lookups, the number of records that acually satisfy our WHERE clause */
SELECT u.id, u.DisplayName, u.LastAccessDate, u.CreationDate, u.Reputation, u.Views
FROM dbo.Users AS u
WHERE u.Reputation = 2
	AND u.Views > 20
ORDER BY u.LastAccessDate DESC;

/* Well, the optimizer expects 27,368 rows back here so it decides to an index seek 
SQL didn't use the index from the missing index recommendation here
*/
SELECT u.id, u.DisplayName, u.LastAccessDate, u.CreationDate, u.Reputation, u.Views
FROM dbo.Users AS u 
WHERE u.Reputation = 1
	AND u.Views > 20
ORDER BY u.LastAccessDate DESC;
GO



/* Key column ordering really does matter */

/* 
Surely having all the columns in you index is all you need to make queries efficient, right?

Not so fast buster.
*/

DROP TABLE IF EXISTS #Promotions; 

CREATE TABLE #Promotions (
Id INT IDENTITY(1, 1) PRIMARY KEY,
Name VARCHAR(50) NOT NULL,
StartDate DATETIME2(2),
EndDate DATETIME2(2));
GO

INSERT INTO #Promotions
(
Name,
StartDate,
EndDate)

SELECT TOP 100000
CONCAT('PROMO-', CAST(id AS VARCHAR(12))) AS Name,
f.StartDate,
f2.EndDate
FROM dbo.Users u
CROSS APPLY (SELECT DATEADD( hh, id* 0.25, '2016-09-01') AS StartDate) f
CROSS APPLY (SELECT DATEADD(dd, ((ABS(CHECKSUM(NEWID())) % 365) + 1), f.StartDate) AS EndDate) f2
ORDER BY u.id;

/*Just to show what we are working with here in the promo table */

SELECT TOP 100 * 
FROM #Promotions
ORDER BY Id; 


/* Now we want to find the active ones so put an index on this */
CREATE INDEX JMR_#Promotions_StartDate_EndDate 
ON #Promotions (StartDate, EndDate)
INCLUDE (Name) ;


/*
In a past iteration this read 96,000 rows to only return around 10,000
Nearly all the have a start date in the past but a very limited number have a start date in the future
*/

SELECT StartDate, EndDate, Name, Id
FROM #Promotions AS p
WHERE  p.EndDate>= SYSDATETIME()
	AND p.StartDate <= SYSDATETIME()
GO


/*
 How many of these records have future end dates?
Only 10-15,000 of these records have a future end date
This is a tiny table so it is only doing 460 reads
*/

SELECT COUNT(1) 
FROM #Promotions AS p
WHERE  p.StartDate <= GETDATE()  -- ~98,000

SELECT COUNT(1) 
FROM #Promotions AS p
WHERE  p.EndDate>= GETDATE() -- ~11,000

/* Create an index keyed on EndDate first */


CREATE INDEX JMR_#Promotions_EndDate_StartDate
ON #Promotions (EndDate, StartDate)
INCLUDE (Name) ;


/* 
Keying this on EndDate and then StartDate now does 60ish reads instead of 450.
The optimizer only needs to read 10-15,000 rows instead of 95,000 rows.
*/
SELECT StartDate, EndDate, Name, Id
FROM #Promotions AS p
WHERE  p.EndDate>= GETDATE()
	AND p.StartDate <= GETDATE()
GO 
/*
The take aways here are 
	Needing to do key lookups to get part of a WHERE clause can be inefficent, move the Predicate into the index.
	Index key order matters a lot.
	Reading lots more rows in an index than are returned can be a red flag.
	Knowing how the is used and distributed can be incredibly helpful.
*/
