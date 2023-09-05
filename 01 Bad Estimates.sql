

USE StackOverflow2010;
GO

SET STATISTICS IO, TIME ON;

EXEC CleanupJMRIndexes;
GO



/* Bad Estimates Are Bad */


/*
Bad estimates are bad!
You can avoid some of them. */

/* Let's start looking at local variables */

DECLARE @Reputation INT = 2

SELECT u.id, u.DisplayName, u.LastAccessDate, u.CreationDate, u.Reputation, u.Views
FROM dbo.Users AS u
WHERE u.Reputation = @Reputation
ORDER BY u.LastAccessDate DESC;
GO

/*
Rather than do Reputation = 2, let's try 1 instead.
Reputation = 1 is the default for a new user who has never done anything.
Now this is doing 122,000 reads, reading the whole users table would only do 7,400 reads
*/

DECLARE @Reputation INT = 1

SELECT u.id, u.DisplayName, u.LastAccessDate, u.CreationDate, u.Reputation, u.Views
FROM dbo.Users AS u
WHERE u.Reputation = @Reputation
ORDER BY u.LastAccessDate DESC;
GO


/* 
What went wrong? 
We have a terrible, no good, very bad estimate. 
We estimated 18 rows and instead got 40,000.
The sort ran out of memory and had to write to tempdb and read data back out, which is much slower than doing the sort in memory.

*/

-- How did SQL get there?
DBCC SHOW_STATISTICS('dbo.Users', IX_Dbo_Users_Reputation)

-- Look at the All density column for OwnerUserId and multiply it by the number of rows in the table

SELECT 6.142506E-05 * 299398.0 -- 18.4




/* 
What happens with a literal value?
SQL decides to do a CI scan here because SQL has actual statistics for Reputation  = 1 and our estimates are dead on.
Doing 7,400 reads is better than 122,000.
*/
SELECT u.id, u.DisplayName, u.LastAccessDate, u.CreationDate, u.Reputation, u.Views
FROM dbo.Users AS u
WHERE u.Reputation = 1
ORDER BY u.LastAccessDate DESC;


/*
Whenever you query for data outside the norm with local variable you are liable to run into estimation problems
*/


/* Let's take the reputation query from earlier and add Views to the where clause */
SELECT u.id, u.DisplayName, u.LastAccessDate, u.CreationDate, u.Reputation, u.Views
FROM dbo.Users AS u
WHERE u.Reputation = 1
	AND u.Views > 20
ORDER BY u.LastAccessDate DESC;

/*
Our estimates versus actual here aren't great 618 is a lot smaller than 27368.
Why could that be?

People with a Reputation of 1 probably haven't done much to make people want to view their accounts
	but SQL doesn't know that. 
*/

/*
How SQL Server comes up with multi column statistics is pretty complicated but this link covers it.
https://techcommunity.microsoft.com/t5/sql-server-support-blog/multi-column-statistics/ba-p/3667253

This example doesn't have a solution where we magically get better statistics for it
	but I can show you the problems bad estimates can cause in your queries and a trick to mitigate that

Now we can use this query as the basis for a larger query */


/*
This does 810,000 reads
*/
SELECT u.id AS OwnerUserId, u.DisplayName, u.LastAccessDate, u.CreationDate, u.Reputation, u.Views,
p.id AS PostId,
p.CommentCount,
p.tags
FROM dbo.Users AS u
	JOIN dbo.Posts AS p ON u.id = p.OwnerUserId
WHERE u.Reputation = 1
	AND u.Views > 20
ORDER BY u.LastAccessDate DESC;

/* 
Well, those estimates are atrocious and we're hashing tons of data together.

What if we extract the user information to a temp table first 
	and then join that to all the other tables after we know how many records we actually have?
*/


DROP TABLE IF EXISTS #Users;
GO

SELECT u.id, u.DisplayName, u.LastAccessDate, u.CreationDate, u.Reputation, u.Views
INTO #Users
FROM dbo.Users AS u
WHERE u.Reputation = 1
	AND u.Views > 20
ORDER BY u.LastAccessDate DESC;



SELECT u.id, u.DisplayName, u.LastAccessDate, u.CreationDate, u.Reputation, u.Views, 
p.id AS PostId,
p.CommentCount,
p.tags
FROM #users AS u
	JOIN dbo.Posts AS p ON u.id = p.OwnerUserId
ORDER BY u.LastAccessDate DESC;

/*
Well, 22,000 reads is a whole lot better than 810,000 and it's much faster.
*/


/*
Takeaways
	Local variables can have bad estimates when the value passed in doesn't conform to the norm for the table.
	Sometimes you get bad estimates, inequality predicates make things worse.
	Bad estimates can mess up all the estimates downstream of them.
	Breaking queries up by dumping steps with bad estimates into temp tables can improve downstream estimates.

*/

