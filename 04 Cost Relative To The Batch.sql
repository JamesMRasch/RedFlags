

USE StackOverflow2010;
GO
SET STATISTICS IO, TIME ON; 

EXEC CleanupJMRIndexes;


/*

SQL has Cost Relative to the batch, can't I just tune by that?

Well, it relies on the estimated cost relative to the batch.
The estimates it has aren't always right.
*/


DROP TABLE IF EXISTS #Posts;
GO 

DECLARE @PostOwnerId INT = 22656

SELECT p.Id AS PostId, p.OwnerUserId, p.AcceptedAnswerId, p.ClosedDate
INTO #Posts 
FROM dbo.Posts AS p WHERE p.OwnerUserId = @PostOwnerId;

			
SELECT p.PostId, p.OwnerUserId, p.ClosedDate, p.AcceptedAnswerId, a.OwnerUserId AS AnswerOwnerUserId
FROM #Posts p
JOIN dbo.Posts AS a
			ON a.id = p.AcceptedAnswerId;

/*
What happens when we actually use a literal instead?
Ooohhhh, this one is fun, it now flips the estimate of which step will be ~95% of the work to be done. 
*/


DROP TABLE IF EXISTS #Posts;
GO 

SELECT p.Id AS PostId, p.OwnerUserId, p.AcceptedAnswerId, p.ClosedDate
INTO #Posts
FROM dbo.Posts AS p WHERE p.OwnerUserId = 22656;

			
SELECT p.PostId, p.OwnerUserId, p.ClosedDate, p.AcceptedAnswerId, a.OwnerUserId AS AnswerOwnerUserId
FROM #Posts p
JOIN dbo.Posts AS a
			ON a.id = p.AcceptedAnswerId;
GO


/*
The takeaway here is that the estimated cost relative to the batch really is just an estimate.
If you're looking for bad performance, rely on other means.

* Looking at logical reads and CPU steps of queries.
* Learning how the operators work
* Try using SQL Sentry Plan Explorer.


*/