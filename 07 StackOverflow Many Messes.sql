

USE StackOverflow2010;
GO
exec  dbo.CleanupJMRIndexes 

SET STATISTICS IO, TIME ON;


/*
This knocks out a bunch of bad patterns at once 
	-- tons of key lookups
	-- going into the same table more than once
	-- correlated subquery
	-- doing an extra join just to aggregate on name instead of id
	-- reveals lumpy data

*/
GO

CREATE OR ALTER PROCEDURE dbo.TopHundredPostsByDisplayName @DisplayName NVARCHAR(40)
AS
BEGIN
    SELECT TOP 100
        p.id AS PostId,
        p.Score,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        (
            SELECT COUNT(1)
            FROM dbo.Votes AS v
                JOIN VoteTypes AS vt
                    ON v.VoteTypeId = vt.Id
            WHERE p.id = v.PostId
                  AND vt.Name = 'Upmod'
        ) AS UpvotesCalculated,
        (
            SELECT COUNT(1)
            FROM dbo.Votes AS v
                JOIN VoteTypes AS vt
                    ON v.VoteTypeId = vt.Id
            WHERE p.id = v.PostId
                  AND vt.Name = 'DownMod'
        ) AS DownvotesCalculated
    FROM dbo.Posts AS p
        JOIN dbo.Users u
            On u.id = p.OwnerUserId
    WHERE u.DisplayName = @DisplayName
    ORDER BY p.Score DESC
END
GO

/* Run for super user Jon Skeet*/


 EXEC dbo.TopHundredPostsByDisplayName @DisplayName = 'Jon Skeet'; 


 /*
 What's going wrong here and really highlighted by Jon Skeet?
 * The correlated subquery is causing the Votes table for upvotes to get queried 100x, once for each post
 * The correlated subquery is causing the Votes table for downvotes to get queried 100x, once for each post
 * About 11,000 key lookups into dbo.Votes to get the vote type
 * Going into the Votes table twice, once for upmod and once for downmod
 * Around 11,000 seeks into dbo.VoteTypes because we are filtering by VoteType.Name instead of Vote.VoteTypeId
 * About 11,000 key lookups into dbo.Posts to get the accepted answer id and score
 * Horrible estimates for the number of posts to be returned starting with dbo.Posts
 */


/* 
Here we can look at breaking this up into pieces with temp tables 
	and see if having temp tables in the interim improves our estimates
*/
GO

CREATE OR ALTER PROCEDURE dbo.TopHundredPostsByDisplayName_JMR  @DisplayName NVARCHAR(40)
AS
BEGIN

DROP TABLE IF EXISTS #Users

/* Here we extract only the user we need into a temp table */
/* This gives gives the optimizer a better clue about the user it is working with in the next step */
SELECT u.id AS UserId 
INTO #Users
FROM dbo.Users AS u
WHERE u.DisplayName =  @DisplayName;


DROP TABLE IF EXISTS #Posts; 


/* 
Create a temp table to hold the posts we care about 
It is always best practice to explictly create temp tables.
In this case it is being created with a PK on PostId which is also the clustering key without a separate CI being created 
This means the data is sorted the way it will need to be 
*/
CREATE TABLE #Posts (
PostId INT NOT NULL, Score INT NOT NULL, OwnerUserId INT NULL, AcceptedAnswerId INT NULL, PRIMARY KEY (PostId)); 


/* 
Load only the 100 posts we want based on the score into a temp table 
Knowing the exact 100 rows we're looking at will dramatically improve our estimates
*/
INSERT INTO #Posts 
SELECT  TOP 100 p.id AS PostId, p.Score, p.OwnerUserId, p.AcceptedAnswerId
FROM dbo.Posts p
	JOIN #Users u ON p.OwnerUserId = u.UserId
ORDER BY Score DESC


DROP TABLE IF EXISTS #Votes
/* 
Load the data we want for votes into a temp table.
Using the 2 case statements here in this aggregation lets us calculate upvotes and downvotes at the same time.
It eliminates the need to go into the same table twice.
A scan of the votes table would do around 46,000 reads.
*/
SELECT p.PostId, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes, 
	SUM(CASE WHEN v.VoteTypeId  = 3 THEN 1 ELSE 0 END) AS Downvotes
INTO #Votes
FROM #Posts p
	JOIN dbo.Votes v ON v.PostId = p.PostId 
GROUP BY p.PostId; 

/* now we join together our data from the 2 temp tables*/
SELECT p.PostId, p.Score, p.OwnerUserId, p.AcceptedAnswerId, v.Upvotes, v.Downvotes 
FROM #Posts  AS p
	JOIN #Votes v ON p.PostId = v.PostId; 
END
GO


/* Run for super user Jon Skeet*/
 EXEC dbo.TopHundredPostsByDisplayName @DisplayName = 'Jon Skeet'; 
 EXEC dbo.TopHundredPostsByDisplayName_JMR @DisplayName = 'Jon Skeet'; 

/* Running all these steps collectively did about 63,000 reads
	compared to 103,000 reads with the original query */


/* We're rewritten it to be less of a mess but what if we also try to eliminate some key lookups?
We have an existing index on dbo.Votes.PostId at the moment, what if we include VoteTypeId as well?
It's not like this will bloat the index too badly
This takes about 7 seconds to run
*/
CREATE INDEX JMR_Dbo_Votes_PostId_INC_VoteTypeId
ON dbo.Votes (PostId)
INCLUDE (VoteTypeId)
WITH (MAXDOP = 0);

/*
Now if we run it for Jon Skeet, we then see that we are saving around 18,000 reads by not having to do 9,000 key lookups
That's great progress. 
*/
 EXEC dbo.TopHundredPostsByDisplayName_JMR @DisplayName = 'Jon Skeet'; 


 
/*
We're also doing 11,000 key lookups on dbo.Posts to get the AcceptedAnswerId and Scoregit
*/
CREATE INDEX JMR_Dbo_Posts_OwnerUserId_INC_AcceptedAnswerId_Score
ON dbo.Posts(OwnerUserId)
INCLUDE (AcceptedAnswerId, Score)
WITH (MAXDOP = 0);

EXEC dbo.TopHundredPostsByDisplayName_JMR @DisplayName = 'Jon Skeet'; 


 




DROP TABLE IF EXISTS #Users



/* Here we extract only the user we need into a temp table */
/* This gives gives the optimizer a better clue about the user it is working with in the next step */
SELECT u.id AS UserId 
INTO #Users
FROM dbo.Users AS u
WHERE u.DisplayName = 'Jon Skeet'


DROP TABLE IF EXISTS #Posts; 


/* Create a temp table to hold the posts we care about */
CREATE TABLE #Posts (
PostId INT NOT NULL, Score INT NOT NULL, OwnerUserId INT NULL, AcceptedAnswerId INT NULL); 


/* Load only the 100 posts we want based on the score into a temp table */
/* Note the great estimates now */
INSERT INTO #Posts 
SELECT  TOP 100 p.id AS PostId, p.Score, p.OwnerUserId, p.AcceptedAnswerId
FROM dbo.Posts p
	JOIN #Users u ON p.OwnerUserId = u.UserId
ORDER BY Score DESC


DROP TABLE IF EXISTS #Votes
/* 
Load the data we want for votes into a temp table.
Using the 2 case statements here in this aggregation lets us calculate upvotes and downvotes at the same time.
A scan of the votes table would do around 46,000 reads
*/
SELECT p.PostId, SUM(CASE WHEN v.VoteTypeId  = 2 THEN 1 ELSE 0 END) AS Upvotes, SUM(CASE WHEN v.VoteTypeId  = 3 THEN 1 ELSE 0 END) AS Downvotes
INTO #Votes
FROM #Posts p
	JOIN dbo.Votes v ON v.PostId = p.PostId 
GROUP BY p.PostId; 

/* now we join together our data from the 2 temp tables*/
SELECT p.PostId, p.Score, p.OwnerUserId, p.AcceptedAnswerId, v.Upvotes, v.Downvotes 
FROM #Posts  AS p
	JOIN #Votes v ON p.PostId = v.PostId; 











-- Try to recreate the query where RKW was doing a full table scan of messages every time it needed to find the date created for each message
-- that was looking up based on ThreadId  which was not indexed
-- I beat it by extracting everything to a temp table and keying the temp table for the join


-- See PostLinks Demo at bottom


-- Is the accepted answer on a post the most recent post??

SELECT TOP 25000 * 
INTO #Posts25000
FROM dbo.Posts p
ORDER BY p.id


CREATE INDEX IX_Dbo_Posts_AcceptedAnswerId
ON dbo.Posts (AcceptedAnswerId);


CREATE INDEX IX_Dbo_Posts_ParentId
ON dbo.Posts (ParentId)

SELECT p.Id,
		CASE WHEN (SELECT TOP (1) sp.Id
					FROM #Posts25000 sp
					WHERE sp.ParentId = p.Id
					ORDER BY CreationDate DESC
					) = aa.id 
					THEN 1
					ELSE 0
					END AnswerIsMostRecentPost
FROM #Posts25000 p
	JOIN #Posts25000 aa ON aa.Id = p.AcceptedAnswerId
OPTION (MAXDOP  1) 




--Posts is ~800k pages
-- I was able to get the subquery to behave roughly how we would have expected but posts is so large of a table this takes forever to run
-- Find a smaller demo set.

SET STATISTICS IO, TIME ON 

SELECT TOP 1500000 p.Id,
	CASE WHEN  (SELECT TOP (1) sp.Id
					FROM dbo.Posts sp
					WHERE sp.ParentId = p.Id) = aa.id
					THEN 1
					ELSE 0 
					END AS AnswerIsMostRecentPost
FROM dbo.Posts p
	LEFT JOIN dbo.Posts aa ON aa.Id = p.AcceptedAnswerId





SELECT u.Id, u.DisplayName, u.CreationDate, f.MaxModDate
FROM dbo.Users u
OUTER APPLY (SELECT MAX(p.LastEditDate) AS MaxModDate
			FROM dbo.Posts p
			WHERE p.OwnerUserId = u.id) f


			

SELECT u.Id, u.DisplayName, u.CreationDate, f.MaxModDate
FROM dbo.Users u
OUTER APPLY (SELECT MAX(p.LastEditDate) AS MaxModDate
			FROM dbo.Posts p
			WHERE p.OwnerUserId = u.id) f


--- Attempt an outer apply demo using users and badges, get say the top 3 badges by date

DECLARE @UserID INT = 22656

SELECT  u.DisplayName, f.Name, f.date
FROM dbo.Users u 
	OUTER APPLY (
				SELECT TOP 3 Name, Date
				FROM Badges b
				WHERE b.UserId = u.Id
				ORDER BY Date DESC ) f
WHERE u.Id = @UserID
GO

CREATE INDEX IX_Badges_UserId_Date
ON dbo.Badges(UserId, Date) 


--Look at Jon Skeet's badges
-- this does about 8 reads, 2,800 key lookups in Badges
SELECT  u.DisplayName, f.Name, f.date
FROM dbo.Users u 
	OUTER APPLY (
				SELECT TOP 1 Name, Date
				FROM Badges b
				WHERE b.UserId = u.Id
				ORDER BY Date DESC ) f
WHERE u.Id = 22656 


--- Convert it to LOJ + Temp Table
-- Wow, performance doesn't really improve that much, we're doing 6 reads becuse of scanning Badges

SET STATISTICS IO, TIME ON 

DROP TABLE IF EXISTS #Badges

SELECT TOP 1 Name, b.Date, b.UserId
INTO #Badges
FROM Badges b
WHERE b.UserId = 22656
ORDER BY b.Date DESC

SELECT u.DisplayName, b.Name, b.Date
FROM dbo.Users u
	LEFT JOIN #Badges b ON u.id = b.UserId



-- Now let's add an index on Badges


CREATE INDEX IX_Badges_UserId_Date
ON dbo.Badges(UserId, Date) 

-- the LOJ now does 10 reads compared ot OA's 8,000 reads but that's because of the index



-- Let's make this uglier, try finding anyone who has a post within a day of their last login and the post type

SELECT TOP 1000 u.Id UserID, u.LastAccessDate, f.PostId, f.CreationDate, f.Type
FROM dbo.Users u
	OUTER APPLY (SELECT p.Id PostId, p.CreationDate, pt.Type
				FROM dbo.Posts p
					JOIN dbo.PostTypes pt ON pt.Id = p.PostTypeId
				WHERE p.OwnerUserId = u.Id
					AND p.CreationDate > DATEADD(DD, -1, u.LastAccessDate)) f
ORDER BY u.LastAccessDate DESC


SELECT TOP 100 u.Id UserID, u.LastAccessDate, f.PostId, f.CreationDate, f.Type
FROM dbo.Users u
	CROSS APPLY (SELECT p.Id PostId, p.CreationDate, pt.Type
				FROM dbo.Posts p
					JOIN dbo.PostTypes pt ON pt.Id = p.PostTypeId
				WHERE p.OwnerUserId = u.Id
					AND p.CreationDate > DATEADD(DD, -1, u.LastAccessDate)) f
ORDER BY u.LastAccessDate DESC


-- Rewrite this to filter on LastAccessDate as well

SELECT MAX(CreationDate) FROM dbo.Posts --2010-12-31 23:58:27.647

DECLARE @StartDate DATETIME = '2010-12-30'
DECLARE @EndDate DATETIME = '2010-12-30 23:59:59'

SELECT u.Id UserID, u.LastAccessDate, f.PostId, f.CreationDate, f.Type
FROM dbo.Users u
	OUTER APPLY (SELECT p.Id PostId, p.CreationDate, pt.Type
				FROM dbo.Posts p
					JOIN dbo.PostTypes pt ON pt.Id = p.PostTypeId
				WHERE p.OwnerUserId = u.Id
					AND p.CreationDate > DATEADD(DD, -1, u.LastAccessDate)) f
WHERE u.LastAccessDate BETWEEN @StartDate AND @EndDate
ORDER BY u.LastAccessDate DESC
GO

-- Can we rewrite this to be less catastrophic via a temp table??


DECLARE @StartDate DATETIME = '2010-12-30'
DECLARE @EndDate DATETIME = '2010-12-30 23:59:59'

DROP TABLE IF EXISTS #Users;

SELECT u.Id, u.LastAccessDate, DATEADD(DD, -1, u.LastAccessDate) AS OneDayPriorToLastAccess
INTO #Users
FROM dbo.Users u
WHERE u.LastAccessDate BETWEEN @StartDate AND @EndDate;

SELECT u.Id AS UserId, p.Id AS PostId, p.CreationDate, pt.Type As PostType
FROM #Users u
	LEFT JOIN dbo.Posts p ON  p.OwnerUserId = u.Id AND p.CreationDate > u.OneDayPriorToLastAccess
	LEFT JOIN dbo.PostTypes pt ON pt.Id = p.PostTypeId;


-- show the evils of basic tables not hashing in case subquery/ apply

SELECT TOP 100 * FROM PostLinks 
SELECT TOP 100 * FROM LinkTypes


-- We need this index so SQL doesn't just decide to scan the post links table, this is where we can watch stuff get messy fast
CREATE INDEX IX_PostLinks_PostId
ON dbo.PostLinks(PostId)
INCLUDE(LinkTypeId)

CREATE INDEX IX_Post_OwnerUserId 
ON dbo.Posts (OwnerUserId)


CREATE INDEX IX_Post_PostTYpeId
ON dbo.Posts (PostTYpeId)

--DROP INDEX IX_PostLinks_PostId ON dbo.PostLinks 

SET STATISTICS IO, TIME ON 

--664 reads to scan the table
SELECT COUNT(1) 
FROM dbo.PostLinks 

SELECT lt.Type
FROM dbo.Posts p
	JOIN PostLinks pl ON pl.PostId = p.Id
	JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId


-- This is a shining example of doing 200k scans of the LinkTYpes table and 200k seeks into PostLinks

SELECT p.OwnerUserId, u.DisplayName, p.id as PostId, p.Title As PostTitle, pt.Type AS PostType,
CASE WHEN EXISTS (
SELECT 1
FROM PostLinks pl 
	JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
	WHERE lt.Type = 'Linked'
		AND pl.PostId = p.Id)
	THEN 1
	ELSE 0 END AS HasLinkedPost
FROM dbo.Users u 
	JOIN dbo.Posts p ON p.OwnerUserId = u.id
	JOIN dbo.PostTypes pt ON pt.Id = p.PostTypeId
WHERE OwnerUserId = 22656
ORDER BY p.CreationDate DESC;

-- Let's show it isn't the fault of the CASE but the correlated subquery

SELECT TOP 10000 p.OwnerUserId, u.DisplayName, p.id as PostId, p.Title As PostTitle, pt.Type AS PostType,
(SELECT TOP 1'Is Linked Post' AS LinkedPost
FROM PostLinks pl 
	JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
	WHERE lt.Type = 'Linked'
		AND pl.PostId = p.Id) As LinkedPost
FROM dbo.Users u 
	JOIN dbo.Posts p ON p.OwnerUserId = u.id
	JOIN dbo.PostTypes pt ON pt.Id = p.PostTypeId
WHERE OwnerUserId = 22656
ORDER BY p.CreationDate DESC;


-- But Jay, I don't want to go hunting for huge execution numbers in the query plan
-- Here's a hack trick to finding if your correlated subquery/APPLY etc is eating up most of your resources.
-- Break the correlation and see what performance looks like, if it drops dramatically you know it came from the subquery


SELECT TOP 10000 p.OwnerUserId, u.DisplayName, p.id as PostId, p.Title As PostTitle, pt.Type AS PostType,
(SELECT TOP 1'Is Linked Post' AS LinkedPost
FROM PostLinks pl 
	JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
	WHERE lt.Type = 'Linked'
		AND 1 = 2) As LinkedPost
FROM dbo.Users u 
	JOIN dbo.Posts p ON p.OwnerUserId = u.id
	JOIN dbo.PostTypes pt ON pt.Id = p.PostTypeId
WHERE OwnerUserId = 22656
ORDER BY p.CreationDate DESC;


-- How can we fix this?
-- Rewrite the subquery to dump into a temp table instead and then just join to that



DROP TABLE IF EXISTS #Results;

SELECT p.OwnerUserId, u.DisplayName, p.id as PostId, p.Title As PostTitle, pt.Type AS PostType
INTO #Results
FROM dbo.Users u 
	JOIN dbo.Posts p ON p.OwnerUserId = u.id
	JOIN dbo.PostTypes pt ON pt.Id = p.PostTypeId
WHERE OwnerUserId = 22656
ORDER BY p.CreationDate DESC;


SELECT x.OwnerUserId, x.DisplayName, x.PostId, x.PostTitle, x.PostType, x.HasLinkedPost
FROM (
SELECT r.OwnerUserId, r.DisplayName, r.PostId, r.PostTitle, r.PostType, 
CASE WHEN pl.PostId IS NOT NULL
	THEN 1
	ELSE 0 END AS HasLinkedPost,
	ROW_NUMBER() OVER (PARTITION BY r.PostId ORDER BY (SELECT 1/0)) AS RowNum
FROM #Results r
	LEFT OUTER JOIN PostLinks pl ON pl.PostId = r.PostId
	LEFT OUTER JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId AND lt.Type = 'Linked'
	) x WHERE x.RowNum = 1;





