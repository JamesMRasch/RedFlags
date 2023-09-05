

USE StackOverflow2010;
GO

EXEC CleanupJMRIndexes;

SET Statistics IO, TIME ON 


/*
Before diving in, what is a correlated subquery?
It is a subquery that depends on the outer query for the values it will look up.
They execute one time for each row that is selected by the outer query. 
When the outer query returns many rows, these can force the optimizer to do lots of reads, 
sometimes more reads than if the query were restructured as we'll see below.
*/

SELECT * FROM dbo.PostTypes -- This has 8 rows. The table itself is 2 pages


DECLARE @OwnerUserId INT = 39677

SELECT p.OwnerUserId,
       u.DisplayName,
       u.Reputation,
       u.CreationDate AS UserCreationDate,
       p.id AS PostId,
       p.CreationDate AS PostCreationDate,
       p.ClosedDate,
       (
           SELECT pt.Type FROM dbo.PostTypes AS pt WHERE pt.id = p.PostTypeId
       ) As PostType
FROM dbo.Posts AS p
    JOIN dbo.Users AS u
        ON p.OwnerUserId = u.id
WHERE p.OwnerUserId = @OwnerUserId
ORDER BY PostId DESC;
GO

/* Our red flag here is that we are doing tons and tons of reads out of a tiny lookup table */

/* If we use a temp table to get everything except post type and then join over to the PostType table we get an efficient query */

DROP TABLE IF EXISTS #Posts;
GO

DECLARE @OwnerUserId INT = 39677

SELECT p.OwnerUserId,
       u.DisplayName,
       u.Reputation,
       u.CreationDate AS UserCreationDate,
       p.id AS PostId,
       p.CreationDate AS PostCreationDate,
       p.ClosedDate,
	   p.PostTypeId
INTO #Posts
FROM dbo.Posts AS p
    JOIN dbo.Users AS u
        ON p.OwnerUserId = u.id
WHERE p.OwnerUserId = @OwnerUserId
ORDER BY PostId DESC;

SELECT  p.OwnerUserId,
       p.DisplayName,
       p.Reputation,
       p.UserCreationDate,
       p.PostId,
       p.PostCreationDate,
       p.ClosedDate,
	   pt.Type AS PostType
FROM #Posts AS p
	JOIN dbo.PostTypes AS pt ON pt.Id = p.PostTypeId; 
GO


/* 
Can we just rewrite the subquery to a case statement to avoid a temp table? 
It works but only if it is an honest to goodness static table
	or you're sure you'll remember to update the case statement every time that table changes.
*/

DECLARE @OwnerUserId INT = 39677

SELECT p.OwnerUserId,
       u.DisplayName,
       u.Reputation,
       u.CreationDate AS UserCreationDate,
       p.id AS PostId,
       p.CreationDate AS PostCreationDate,
       p.ClosedDate,
       CASE WHEN p.PostTypeId = 1 THEN 'Question'
			WHEN p.PostTypeId = 2 THEN 'Answer'
			WHEN p.PostTypeId = 3 THEN 'Wiki'
			WHEN p.PostTypeId = 4 THEN 'TagWikiExerpt'
			WHEN p.PostTypeId = 5 THEN 'TagWiki'
			WHEN p.PostTypeId = 6 THEN 'ModeratorNomination'
			WHEN p.PostTypeId = 7 THEN 'WikiPlaceholder'
			WHEN p.PostTypeId = 8 THEN 'PrivilegeWiki' END PostTYpe
FROM dbo.Posts AS p
    JOIN dbo.Users AS u
        ON p.OwnerUserId = u.id
WHERE p.OwnerUserId = @OwnerUserId
ORDER BY PostId DESC;
GO
 
