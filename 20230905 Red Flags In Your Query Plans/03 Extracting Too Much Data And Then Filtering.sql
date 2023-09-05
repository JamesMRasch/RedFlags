

USE StackOverflow2010;
GO

exec  dbo.CleanupJMRIndexes

SET STATISTICS IO, TIME ON

/*
	The following proc gets some user information, details about their most recent post, 
		and the last time someone voted on that post.

*/

GO
CREATE OR ALTER PROCEDURE dbo.StoGetUserPostInfo @OwnerUserId INT
AS
BEGIN

    DROP TABLE IF EXISTS #PostInfo;

    SELECT p.OwnerUserId,
           u.DisplayName,
           u.Reputation,
           u.CreationDate AS UserCreationDate,
           p.id AS PostId,
           p.CreationDate AS PostCreationDate,
           p.ClosedDate,
           mvd.QuestionLastVoteDate
    INTO #PostInfo
    FROM dbo.Posts AS p
        LEFT JOIN dbo.Users AS u
            ON p.OwnerUserId = u.id
        OUTER APPLY
    (
        SELECT MAX(v.CreationDate) AS QuestionLastVoteDate
        FROM dbo.Votes AS v
        WHERE p.id = v.PostId
    ) AS mvd
    WHERE p.OwnerUserId = @OwnerUserId
          AND p.PostTypeId = 1 /* Question */
    ORDER BY PostId DESC

	/* now we select out the most recent post */
    SELECT TOP 1
        p.ownerUserId,
        p.DisplayName,
        p.Reputation,
        p.UserCreationDate,
        p.PostId AS PostId,
        p.PostCreationDate,
        p.ClosedDate,
        p.QuestionLastVoteDate
    FROM #PostInfo AS p
    ORDER BY PostId DESC

END
GO

/*
Now we run it for a normal user
This does 348 reads
The reads don't really look terrible but if we examine the query plan, we find a residual predicate.
This plan is also subject to parameter sniffing but that is a topic beyond this current presentation
Most users have few posts so we'll assume this is fairly representitive of the plan that generally goes into cache.
*/


EXEC StoGetUserPostInfo @OwnerUserId = 22

SELECT COUNT(1)
FROM dbo.Posts AS p
WHERE p.OwnerUserId = 22 --64
      AND p.PostTypeId = 1 --9



-- What happens when we look at a someone who asked lots more questions?
-- This is doing 19,000 read 1,000 key lookups into dbo.Posts and then 1,800 seeks and key lookups into dbo.Votes.
EXEC dbo.StoGetUserPostInfo @OwnerUserId = 39677


-- What happens when when we run it for the default user 0?
-- Things get even worse. It now takes like 30 seconds.
-- This dos about 1M reads
-- EXEC dbo.StoGetUserPostInfo @OwnerUserId = 0


/*
Extracting extra data and then filtering it at the end is not an efficent pattern.
This was inspired by a procedure that was extracting order data and then only getting data for 
	the most recent order at the end.
It ran into real problems for an internal transfer user with hundreds of thousands of "orders".
*/

/* 
	This rewrites the procedure to only process the information it needs 
	We first extract the user and post information and then look up the most recent vote date in a separate step
*/
GO

CREATE OR ALTER PROCEDURE dbo.StoGetUserPostInfoLimited @OwnerUserId INT
AS
BEGIN

    DROP TABLE IF EXISTS #PostInfo;


    DECLARE @MaxVoteDate DATETIME

	/* Here out of the gate we'll get just the TOP 1 post we are concerned about */
    SELECT TOP 1
        p.ownerUserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        p.id AS PostId,
        p.CreationDate AS PostCreationDate,
        p.ClosedDate
    INTO #PostInfo
    FROM dbo.Posts AS p
        LEFT JOIN dbo.Users AS u
            ON p.OwnerUserId = u.id
    WHERE p.OwnerUserId = @OwnerUserId
          AND p.PostTypeId = 1
    ORDER BY PostId DESC

	/* now we look up just the max CreationDate for the single post */
    SELECT @MaxVoteDate = MAX(v.CreationDate)
    FROM #PostInfo AS p
        LEFT JOIN dbo.Votes AS v
            ON p.PostId = v.PostId


    SELECT p.ownerUserId,
           p.DisplayName,
           p.Reputation,
           p.UserCreationDate,
           p.PostId AS PostId,
           p.PostCreationDate,
           p.ClosedDate,
           @MaxVoteDate AS QuestionLastVoteDate
    FROM #PostInfo AS p
    ORDER BY PostId DESC

END


EXEC dbo.StoGetUserPostInfoLimited @OwnerUserId = 22; -- 60 reads instead of 350


EXEC dbo.StoGetUserPostInfoLimited @OwnerUserId = 39677; -- 18 reads instead of 19,000


EXEC dbo.StoGetUserPostInfoLimited @OwnerUserId = 0; --around 1,000 reads instead of 1M


/*
Takeaway

Filter data as early as possible

*/