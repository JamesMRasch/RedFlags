
/* 
This script will help set up your instance and database 
	to match the configuration of mine if you find yourself wanting 
	to run the demo scripts.
This takes about 2 minutes to run.
*/

USE StackOverflow2010_index;
GO

/* Set Cost Threshold For Parallelsim to 50 */
EXEC sp_configure 'show advanced options', 1 ;  
GO  
RECONFIGURE  
GO  
EXEC sp_configure 'cost threshold for parallelism', 50 ;  
GO  
RECONFIGURE  
GO  

/* MAXDOP was not set with any thought, it is just the number I have been using for these demos.  */

EXEC sp_configure 'show advanced options', 1;  
GO  
RECONFIGURE WITH OVERRIDE;  
GO  
EXEC sp_configure 'max degree of parallelism', 8;  
GO  
RECONFIGURE WITH OVERRIDE;  
GO  

/* Drop all non-clustered indexes */

	DROP TABLE IF EXISTS #DropIndexes;

	DECLARE @Ctr INT = 1
	DECLARE @MaxId INT
	DECLARE @SqlString NVARCHAR(MAX)

	
	CREATE TABLE #DropIndexes (Id INT IDENTITY(1, 1), SqlString NVARCHAR(MAX));

	INSERT INTO #DropIndexes ( SqlString)
	SELECT CONCAT('DROP INDEX IF EXISTS ', i.name, ' ON ', s.name, '.', o.name, ';')
	FROM sys.indexes i
		JOIN sys.objects o ON o.object_id = i.object_id
		JOIN sys.schemas s ON s.schema_id = o.schema_id
	WHERE i.type = 2 
		AND o.is_ms_shipped = 0; 

	SELECT @MaxId = MAX(Id) FROM #DropIndexes;

	WHILE @Ctr <= @MaxId
	BEGIN
		SELECT @SqlString = d.SqlString
		FROM #DropIndexes AS d
		WHERE d.Id = @Ctr

		EXEC sp_executesql @stmt = @SqlString;

		SELECT @Ctr = @Ctr + 1
	END


/* Create all the non-clustered index I have been using */

--Posts
CREATE INDEX IX_Dbo_Posts_AcceptedAnswerId
ON dbo.Posts(AcceptedAnswerId)
WITH (MAXDOP = 0);

CREATE INDEX IX_Dbo_Posts_OwnerUserId
ON dbo.Posts(OwnerUserId)
WITH (MAXDOP = 0);

CREATE INDEX IX_Post_PostTYpeId
ON dbo.Posts (PostTYpeId)
WITH (MAXDOP = 0);

CREATE INDEX IX_Dbo_Posts_ParentId
ON dbo.Posts (ParentId)
WITH (MAXDOP = 0);

--Users

CREATE INDEX IX_Dbo_Users_DisplayName
ON dbo.Users(DisplayName) 
WITH (MAXDOP = 0);

CREATE INDEX IX_Dbo_Users_Reputation
ON dbo.Users(Reputation) 
WITH (MAXDOP = 0);

--Comments

CREATE INDEX IX_Dbo_Comments_UserId
ON dbo.Comments(UserId)
WITH (MAXDOP = 0);

CREATE INDEX IX_Dbo_Comments_PostId
ON dbo.Comments(PostId)
WITH (MAXDOP = 0);

--Votes

CREATE INDEX IX_Dbo_Votes_UserId
ON dbo.Votes(UserId)
WITH (MAXDOP = 0);

CREATE INDEX IX_Dbo_Votes_PostId
ON dbo.Votes(PostId)
WITH (MAXDOP = 0);

--PostLinks
CREATE INDEX IX_PostLinks_PostId
ON dbo.PostLinks(PostId)
INCLUDE(LinkTypeId)
WITH (MAXDOP = 0);





