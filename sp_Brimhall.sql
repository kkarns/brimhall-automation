IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'sp_Brimhall')
    EXEC ('CREATE PROCEDURE dbo.sp_Brimhall AS SELECT ''temporary holding procedure''')
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE sp_Brimhall
    @TargetLinkName     NVARCHAR(256)   = NULL ,
	@NDays				INT				= NULL ,
    @OutputDatabaseName NVARCHAR(256)   = NULL ,
    @OutputSchemaName   NVARCHAR(256)   = NULL ,
    @OutputTableName    NVARCHAR(256)   = NULL 
AS
-----------------------------------------------------------------------------------------------
-- 
-- name:    
--      sp_Brimhall - a stored procedure wrapper around Jason Brimhall's default trace query for security events      
--
--      credits to Jason Brimhall for the idea from his T-SQL Tuesday blog post: 
--          http://jasonbrimhall.info/2018/07/10/just-cant-cut-that-cord/
--
-- syntax:
--      EXEC sp_Brimhall @TargetLinkName = N'LINKED.SERVER.NAME', @NDays = 1, @OutputDatabaseName = N'MASTER', @OutputSchemaName   = N'dbo', @OutputTableName    = N'DefTracePermissions';
--
-- dependencies:
--      1) a job to run this via Powershell daily
--      2) pre-existing linked server connections for target servers
--
-- updated:
--      -- Tuesday, October 2, 2018 4:37 PM
-- 

BEGIN
--SET NOCOUNT ON;


DECLARE @sqlcmd NVARCHAR(4000);
SET @sqlcmd = N'INSERT INTO ' +
+ @OutputDatabaseName + '.'
+ @OutputSchemaName + '.'
+ @OutputTableName
+ ' (
    SvrName,
    EventTimeStamp,
    EventCategory,
    spid,
    subclass_name,
    LoginName,
    DBUserName,
    HostName,
    DatabaseName,
    ObjectName,
    TargetUserName,
    TargetLoginName,
    SchemaName,
    RoleName,
    TraceEvent
    )
SELECT 
    SvrName,
    EventTimeStamp,
    EventCategory,
    spid,
    subclass_name,
    LoginName,
    DBUserName,
    HostName,
    DatabaseName,
    ObjectName,
    TargetUserName,
    TargetLoginName,
    SchemaName,
    RoleName,
    TraceEvent
FROM OPENQUERY
    (
    [' + @TargetLinkName + '],
''DECLARE @Path VARCHAR(512)
,@StartTime DATE
,@EndTime   DATE = getdate()
-- These date ranges will need to be changed between initial run and maintenance runs
SET @StartTime = dateadd(dd, datediff(dd, 0, @EndTime) - ' + CAST(@NDays AS VARCHAR(80)) + ', 0)
SELECT @Path = REVERSE(SUBSTRING(REVERSE([PATH]), 
    CHARINDEX(''''\'''', REVERSE([path])), 260)) + N''''LOG.trc''''
    FROM sys.traces 
    WHERE is_default = 1;
SELECT 
    @@servername as SvrName,
    gt.StartTime AS EventTimeStamp, 
    tc.name AS EventCategory,
    spid,
    tv.subclass_name,
    gt.LoginName,
    gt.DBUserName,
    gt.HostName,
    gt.DatabaseName,
    gt.ObjectName,
    gt.TargetUserName,
    gt.TargetLoginName,
    gt.ParentName AS SchemaName,
    gt.RoleName,
    te.name AS TraceEvent
FROM ::fn_trace_gettable( @path, DEFAULT ) gt
INNER JOIN sys.trace_events te
    ON gt.EventClass = te.trace_event_id
INNER JOIN sys.trace_categories tc
    ON te.category_id = tc.category_id
INNER JOIN sys.trace_subclass_values tv
    ON gt.EventSubClass = tv.subclass_value AND 
    gt.EventClass = tv.trace_event_id
WHERE 
    1 = 1
    AND CONVERT(date,gt.StartTime) >= @StartTime 
    AND CONVERT(date,gt.StartTime) <= @EndTime
    and tc.name = ''''Security Audit''''
    AND gt.TargetLoginName IS NOT NULL
ORDER BY 
    gt.StartTime;'');
';

PRINT @sqlcmd;
EXEC(@sqlcmd);



END
GO