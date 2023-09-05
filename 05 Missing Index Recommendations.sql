
USE StackOverflow2010;
GO

EXEC CleanupJMRIndexes;

SET STATISTICS IO, TIME ON;

DROP TABLE IF EXISTS #Temp;

SELECT 
    id,
    CAST(0 AS INT) AS NotSelective,
    DisplayName,
    AboutMe,
    Reputation,
    Location,
    CreationDate
INTO #Temp
FROM dbo.Users

ALTER TABLE #Temp ADD CONSTRAINT PK_Temp PRIMARY KEY CLUSTERED (Id);

CREATE NONCLUSTERED INDEX IX_Temp_CreationDate ON #Temp (CreationDate);



-- 5731 reads
SELECT DisplayName,
       Reputation
FROM #Temp
WHERE DisplayName = 'Alex'
      AND NotSelective = 0
ORDER BY Reputation;



-- Ok, let's create the index that SQL suggested.
CREATE INDEX IX_#Temp_MissingIndexRecommendation
ON #Temp
(
    NotSelective,
    DisplayName
);

/*
2500 reads, well that's a whole lot better than 5,700 reads
But you will note we are doing a key lookup here, 
SQL didn't tell us to do anything with reputation
(this is they folks in the business call foreshadowing)
*/


SELECT DisplayName,
       Reputation
FROM #Temp
WHERE DisplayName = 'Alex'
      AND NotSelective = 0
ORDER BY Reputation;

/*
To be fair, if you read the documentation 
	Microsoft has a long list of disclaimers about missing index recommendations 
	including that key columns are not in any order.
	https://learn.microsoft.com/en-us/sql/relational-databases/indexes/tune-nonclustered-missing-index-suggestions?view=sql-server-ver16
*/


/* Just to prove a point, we can also write a better index by keying on reputation as well */

DROP INDEX IF EXISTS JMR ON #Temp

CREATE INDEX JMR ON #Temp (DisplayName, NotSelective, Reputation);


/*
We now do 7 reads here instead of 2560.
Instead of having to do 831 key lookups to get the reputations and the do a sort
	it is all in our index and SQL can just dive bomb in for what we need.
*/
SELECT DisplayName,
       Reputation
FROM #Temp
WHERE DisplayName = 'Alex'
      AND NotSelective = 0
ORDER BY Reputation;




/*
Now we create a copy of our temp table but make NotSelective the last column in the table
*/


DROP TABLE IF EXISTS #Temp2;

SELECT 
    id,
    DisplayName,
    AboutMe,
    Reputation,
    Location,
    CreationDate,
    CAST(0 AS INT) AS NotSelective
INTO #Temp2
FROM dbo.Users

ALTER TABLE #Temp2 ADD CONSTRAINT PK_Temp2 PRIMARY KEY CLUSTERED (Id);

CREATE NONCLUSTERED INDEX IX_Temp2_CreationDate ON #Temp2 (CreationDate);

/*
you will now note that display name appears in the missing index rec first
	followed by NotSelective.
*/
SELECT DisplayName,
       Reputation
FROM #Temp2
WHERE DisplayName = 'Alex'
      AND NotSelective = 0
ORDER BY Reputation;


/*
Takeaway

Missing index recommendations may not be perfect.
Microsoft says user beware all the limitations on these recs.
It is possible to add a recommended index but SQL decides to not use it and keep recommending the index 
	(no I don't have an example today but I did see the same index 7 times on a table once)
*/
