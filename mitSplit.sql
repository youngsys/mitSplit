SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[pageHeaders](
	[headerText] [varchar](100) NOT NULL,
	[maxOffsetFromTop] [int] NOT NULL,
	[minOffsetFromTop] [int] NOT NULL,
	[indicatesNotNewPage] [char](1) NULL,
	[documentType] [varchar](30) NULL,
	[documentTypeScore] [int] NULL
) ON [PRIMARY]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[pdfFile](
	[pkPDF] [int] IDENTITY(1,1) NOT NULL,
	[pdfName] [varchar](200) NOT NULL,
	[processed] [char](1) NULL
) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
CREATE UNIQUE CLUSTERED INDEX [UK_pdfFile] ON [dbo].[pdfFile]
(
	[pdfName] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = ON, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[pdfPage](
	[pkPdfPage] [int] IDENTITY(1,1) NOT NULL,
	[fkPdfFile] [int] NULL,
	[processed] [char](1) NULL,
	[pageText] [varchar](max) NULL,
	[pdfPageNumber] [int] NULL,
	[hasPageHeaders] [char](1) NULL,
	[hdrPageNo1] [int] NULL,
	[hdrPageNo1Score] [int] NULL,
	[hdrPageNo2] [int] NULL,
	[hdrPageNo2Score] [int] NULL,
	[hdrPageNo3] [int] NULL,
	[hdrPageNo3Score] [int] NULL,
	[ftrPageNo1] [int] NULL,
	[ftrPageNo1Score] [int] NULL,
	[ftrPageNo2] [int] NULL,
	[ftrPageNo2Score] [int] NULL,
	[bestPageNo] [int] NULL,
	[bestPageNoScore] [int] NULL,
	[docNo] [int] NULL,
	[docPageNo] [int] NULL,
	[docType] [varchar](30) NULL,
	[cleanText] [varchar](max) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
CREATE CLUSTERED INDEX [IX_pdfPage] ON [dbo].[pdfPage]
(
	[fkPdfFile] ASC,
	[pdfPageNumber] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
CREATE UNIQUE NONCLUSTERED INDEX [UK_pdfPage] ON [dbo].[pdfPage]
(
	[fkPdfFile] ASC,
	[pdfPageNumber] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = ON, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[uspAnalysePageNumbers] (
	@pageNoField	VARCHAR(20),
	@doAnalysis		CHAR(1) = 'N'
) AS
BEGIN
	SET NOCOUNT ON
	DECLARE @sql VARCHAR(MAX)

	-- remove spurious page numbers
	SET @sql = '
			UPDATE	pg2
			SET		pg2."hdrPageNo1" = NULL
			FROM	"pdfPage" pg1
			JOIN	"pdfPage" pg2
			ON		pg2."fkPdfFile" = pg1."fkPdfFile"
			AND		pg2."pdfPageNumber" = pg1."pdfPageNumber" +1
			JOIN	"pdfPage" pg3
			ON		pg3."fkPdfFile" = pg2."fkPdfFile"
			AND		pg3."pdfPageNumber" = pg2."pdfPageNumber" +1
			WHERE	pg3."hdrPageNo1" = pg1."hdrPageNo1" +2
			AND		pg2."hdrPageNo1" <> pg1."hdrPageNo1" +1'

	SET @sql = REPLACE(@sql,'hdrPageNo1',@pageNoField)
	EXEC (@sql)

	-- record the number of pages in a run of page numbers where there are big gaps 
	-- but the ones that are there are consistent
	EXEC uspIdentifyPageNumberRunsWithGaps @pageNoField

	-- record the number of pages in a run of page numbers
	EXEC uspIdentifyPageNumberRuns @pageNoField

	-- fill in the gaps
	EXEC uspFillGaps @pageNoField

	-- record the number of pages in a run of page numbers
	EXEC uspIdentifyPageNumberRuns @pageNoField


	-- clear down where we didn't manage to fill a gap
	-- ie we based the run on ISNULLs and went past the last real pageNo
	-- in uspIdentifyPageNumberRunsWithGaps
	SET @sql = '
		UPDATE	"pdfPage"
		SET		"hdrPageNo1Score" = NULL
		WHERE	"hdrPageNo1Score" IS NOT NULL
		AND		"hdrPageNo1" IS NULL'

	SET @sql = REPLACE(@sql,'hdrPageNo1',@pageNoField)
	EXEC (@sql)


	-- record the page numbers with the highest scoring run length
	IF @doAnalysis = 'Y'
	BEGIN
		UPDATE	"pdfPage"
		SET		"bestPageNo" = 
					CASE
						WHEN	"hdrPageNo1Score" >= ISNULL("hdrPageNo2Score",0) AND
								"hdrPageNo1Score" >= ISNULL("hdrPageNo3Score",0) AND
								"hdrPageNo1Score" >= ISNULL("ftrPageNo1Score",0) AND
								"hdrPageNo1Score" >= ISNULL("ftrPageNo2Score",0)
						THEN	"hdrPageNo1"

						WHEN	"hdrPageNo2Score" >= ISNULL("hdrPageNo1Score",0) AND
								"hdrPageNo2Score" >= ISNULL("hdrPageNo3Score",0) AND
								"hdrPageNo2Score" >= ISNULL("ftrPageNo1Score",0) AND
								"hdrPageNo2Score" >= ISNULL("ftrPageNo2Score",0)
						THEN	"hdrPageNo2"

						WHEN	"hdrPageNo3Score" >= ISNULL("hdrPageNo1Score",0) AND
								"hdrPageNo3Score" >= ISNULL("hdrPageNo2Score",0) AND
								"hdrPageNo3Score" >= ISNULL("ftrPageNo1Score",0) AND
								"hdrPageNo3Score" >= ISNULL("ftrPageNo2Score",0)
						THEN	"hdrPageNo3"

						WHEN	"ftrPageNo1Score" >= ISNULL("hdrPageNo1Score",0) AND
								"ftrPageNo1Score" >= ISNULL("hdrPageNo2Score",0) AND
								"ftrPageNo1Score" >= ISNULL("hdrPageNo3Score",0) AND
								"ftrPageNo1Score" >= ISNULL("ftrPageNo2Score",0)
						THEN	"ftrPageNo1"

						WHEN	"ftrPageNo2Score" >= ISNULL("hdrPageNo1Score",0) AND
								"ftrPageNo2Score" >= ISNULL("hdrPageNo2Score",0) AND
								"ftrPageNo2Score" >= ISNULL("hdrPageNo3Score",0) AND
								"ftrPageNo2Score" >= ISNULL("ftrPageNo1Score",0)
						THEN	"ftrPageNo2"
					END
		WHERE	"hdrPageNo1Score" IS NOT NULL
		OR		"hdrPageNo2Score" IS NOT NULL
		OR		"hdrPageNo3Score" IS NOT NULL
		OR		"ftrPageNo1Score" IS NOT NULL
		OR		"ftrPageNo2Score" IS NOT NULL


		-- fill in the gaps
		EXEC uspFillGaps 'bestPageNo', 'Y'

		-- generate a pageNoRun to use as an indicator of no pagebreak
		EXEC uspIdentifyPageNumberRuns 'bestPageNo'

		-- clear down spurious pagebreaks
		UPDATE	pg
		SET		pg."hasPageHeaders" = NULL
		FROM	"pdfPage" pg
		JOIN	"pdfPage" prv
		ON		prv."fkPdfFile" = pg."fkPdfFile"
		AND		prv."pdfPageNumber" = pg."pdfPageNumber" -1
		AND		(	prv."bestPageNoScore" = pg."bestPageNoScore"
		OR			pg."bestPageNo" IN (2,3)
		OR			(	prv."hasPageHeaders" IS NOT NULL AND
						(	prv."bestPageNoScore" IS NULL OR
							pg."bestPageNoScore" IS NULL
						)
					)
				)
		WHERE	pg."hasPageHeaders" IS NOT NULL

		-- apply document ids and pageNos within each doc
		EXEC uspSetDocumentPages

		-- set the documentTypes
		UPDATE	pg
		SET		pg."docType" = ISNULL(typ.documentType,'Other')
		FROM	"pdfPage" pg
		LEFT	JOIN	(	
					SELECT	pg."docNo"
					,		hdr."documentType"
					,		SUM(hdr."documentTypeScore") AS "Score"
					,		RANK() OVER (PARTITION BY pg."docNo" ORDER BY SUM(hdr."documentTypeScore") DESC) AS "rank"
					FROM	"pdfPage" pg
					JOIN	"pageHeaders" hdr
					ON		hdr."documentType" IS NOT NULL
					AND		pg."pageText" LIKE '%' + hdr."headerText" + '%'
					GROUP	BY pg."docNo"
					,		hdr."documentType"
				) typ
		ON		typ."docNo" = pg."docNo"
		AND		typ."rank" = 1
		AND		typ."Score" > 1
		WHERE	pg."hasPageHeaders" = 'Y'
	END

END
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[uspComposePdfs]
AS
BEGIN
	SET NOCOUNT ON

	;WITH cte AS (
		SELECT	fl."pkPDF"
		,		REPLACE(fl."pdfName",'.pdf','') AS "pdfName"
		,		sub."docType" + 
					CASE
						WHEN "docTypeInstance" > 1
						THEN '_' + CONVERT(VARCHAR(2),"docTypeInstance")
						ELSE ''
					END AS "docType"
		,		sub."firstPage"
		,		sub."lastPage"
		,		sub."docType" AS "rawDocType"
		FROM	"pdfFile" fl
		JOIN	(	SELECT	low."fkPdfFile"
					,		low."docType"
					,		low."pdfPageNumber" AS "firstPage"
					,		MIN(high."pdfPageNumber" - CASE WHEN high."docType" IS NULL THEN 0 ELSE 1 END) AS "lastPage"
					,		ROW_NUMBER() OVER (PARTITION BY low."fkPdfFile", low."docType" ORDER BY low."pdfPageNumber") AS "docTypeInstance"
					FROM	"pdfPage" low
					JOIN	"pdfPage" high
					ON		high."fkPdfFile" = low."fkPdfFile"
					AND		high."pdfPageNumber" > low."pdfPageNumber"
					WHERE	low."docType" IS NOT NULL
					AND		(	high."docType" IS NOT NULL
					OR			high."pdfPageNumber" = (
									SELECT	MAX("pdfPageNumber")
									FROM	"pdfPage" pd2
									WHERE	pd2."fkPdfFile" = low."fkPdfFile"
							))
					GROUP	BY low."fkPdfFile"
					,		low."docType"
					,		low."pdfPageNumber"
				) sub
		ON		sub."fkPdfFile" = fl."pkPDF"
	)
	SELECT	doc."pkPDF"
	,		doc."pdfName" + '_' + doc."docType" + '_' + amt."docType" + '.pdf' AS "pdfName"
	,		amt."firstPage"
	,		amt."lastPage"
	FROM	cte doc
	JOIN	cte amt
	ON		amt."pkPDF" = doc."pkPDF"
	WHERE	doc."rawDocType" NOT IN ('Amendment','Other')
	AND		amt."rawDocType" = 'Amendment'
		UNION ALL
	SELECT	"pkPDF"
	,		"pdfName" + '_' + "docType" + '.pdf' AS "pdfName"
	,		"firstPage"
	,		"lastPage"
	FROM	cte
	WHERE	"rawDocType" <> 'Amendment'
	ORDER	BY 1,3

END
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[uspFillGaps] (
	@pageNoField	VARCHAR(20),
	@doAnalysis		CHAR(1) = 'N'
)
AS
BEGIN
	SET NOCOUNT ON
	DECLARE @sql VARCHAR(MAX)

	SET @sql = '
		UPDATE	pg
		SET		"hdrPageNo1" = pgBase."hdrPageNo1" + pg."pdfPageNumber" - pgBase."pdfPageNumber"
		FROM	"pdfPage" pg
		JOIN	(	SELECT	"fkPdfFile"
					,		MIN("runEndPage") AS "runEndPage"
					,		"runStartPage"
					FROM	(	SELECT	"fkPdfFile"
								,		"runEndPage"
								,		MAX("runStartPage") AS "runStartPage"
								FROM	(	SELECT	runEnd."fkPdfFile"
											,		runEnd."pdfPageNumber" AS "runEndPage"
											,		runStart."pdfPageNumber" AS "runStartPage"
											FROM	(	SELECT	low."fkPdfFile"
														,		low."pdfPageNumber"
														,		low."hdrPageNo1"
														,		low."hdrPageNo1Score" AS "Score"
														FROM	"pdfPage" low
														JOIN	"pdfPage" high
														ON		high."fkPdfFile" = low."fkPdfFile"
														AND		high."pdfPageNumber" = low."pdfPageNumber" +1
														WHERE	low."hdrPageNo1" IS NOT NULL
														AND		high."hdrPageNo1" IS NULL
													) runEnd
											JOIN	(	SELECT	high."fkPdfFile"
														,		high."pdfPageNumber"
														,		high."hdrPageNo1"
														,		high."hdrPageNo1Score" AS "Score"
														FROM	"pdfPage" high
														JOIN	"pdfPage" low
														ON		low."fkPdfFile" = high."fkPdfFile"
														AND		low."pdfPageNumber" = high."pdfPageNumber" -1
														WHERE	high."hdrPageNo1" IS NOT NULL
														AND		low."hdrPageNo1" IS NULL
													) runStart
											ON		runStart."fkPdfFile" = runEnd."fkPdfFile"
											AND		runStart."pdfPageNumber" > runEnd."pdfPageNumber"
											AND		runStart."hdrPageNo1" - runStart."pdfPageNumber" + runEnd."pdfPageNumber" = runEnd."hdrPageNo1"
											AND		(1=2 OR runEnd."Score" IS NOT NULL OR runStart."Score" IS NOT NULL)
											LEFT	JOIN "pdfPage" pig
											ON		pig."fkPdfFile" = runEnd."fkPdfFile"
											AND		pig."pdfPageNumber" > runEnd."pdfPageNumber"
											AND		pig."hdrPageNo1" - pig."pdfPageNumber" + runEnd."pdfPageNumber" <> runEnd."hdrPageNo1"
											WHERE	pig."fkPdfFile" IS NULL
										) gapsToFill
								GROUP	BY "fkPdfFile"
								,		"runEndPage"
							) gapEnds
					GROUP	BY "fkPdfFile"
					,		"runStartPage"
				) gp
		ON		pg."fkPdfFile" = gp."fkPdfFile"
		AND		pg."pdfPageNumber" BETWEEN gp."runEndPage" AND gp."runStartPage"
		AND		pg."hdrPageNo1" IS NULL
		JOIN	"pdfPage" pgBase
		ON		pgBase."fkPdfFile" = gp."fkPdfFile"
		AND		pgBase."pdfPageNumber" = gp."runEndPage"'

	SET @sql = REPLACE(@sql,'hdrPageNo1',@pageNoField)

	IF @doAnalysis = 'Y' 
	BEGIN
		SET @sql = REPLACE(@sql,'1=2','1=1')
	END

	EXEC (@sql)

END

GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[uspIdentifyPageNumberRuns] (
	@pageNoField	VARCHAR(20)
) AS
BEGIN
	SET NOCOUNT ON
	DECLARE @sql VARCHAR(MAX)

	-- record the number of pages in a run of page numbers
	SET @sql = '
			WITH "cte" AS (
				SELECT	high."fkPdfFile"
				,		high."pdfPageNumber" AS "firstPage"
				,		high."pdfPageNumber"
				,		high."hdrPageNo1"
				FROM	"pdfPage" high
				JOIN	"pdfPage" nxt
				ON		nxt."fkPdfFile" = high."fkPdfFile"
				AND		nxt."pdfPageNumber" = high."pdfPageNumber" +1
				AND		nxt."hdrPageNo1" = high."hdrPageNo1" +1
				LEFT	JOIN "pdfPage" low
				ON		low."fkPdfFile" = high."fkPdfFile"
				AND		low."pdfPageNumber" = high."pdfPageNumber" -1
				AND		low."hdrPageNo1" = high."hdrPageNo1" -1
				WHERE	high."pdfPageNumber"=1
				OR		low."pdfPageNumber" IS NULL
					UNION ALL
				SELECT	high."fkPdfFile"
				,		low."firstPage"
				,		high."pdfPageNumber"
				,		high."hdrPageNo1"
				FROM	"cte" low
				JOIN	"pdfPage" high
				ON		high."fkPdfFile" = low."fkPdfFile"
				AND		high."pdfPageNumber" = low."pdfPageNumber" +1
				AND		high."hdrPageNo1" = low."hdrPageNo1" +1
			)
			UPDATE	pg
			SET		pg."hdrPageNo1Score" = run."pageCount"
			FROM	(	SELECT	"fkPdfFile"
						,		"firstPage"
						,		MAX("pdfPageNumber") AS "lastPage"
						,		MAX("pdfPageNumber") - "firstPage" +1 AS "pageCount"
						FROM	"cte"
						GROUP	BY "fkPdfFile"
						,		"firstPage"
						HAVING	MAX("pdfPageNumber") - "firstPage" +1 >2
					) run
			JOIN	"pdfPage" pg
			ON		pg."fkPdfFile" = run."fkPdfFile"
			AND		pg."pdfPageNumber" BETWEEN run."firstPage" AND run."lastPage"'

	SET @sql = REPLACE(@sql,'hdrPageNo1',@pageNoField)
	EXEC (@sql)

END

GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[uspIdentifyPageNumberRunsWithGaps] (
	@pageNoField	VARCHAR(20)
) AS
BEGIN
	SET NOCOUNT ON
	DECLARE @sql VARCHAR(MAX)

	-- record the number of pages in a run of page numbers where there are big gaps 
	-- but the ones that are there are consistent
	SET @sql = '
			WITH "cte" AS (
				SELECT	high."fkPdfFile"
				,		high."pdfPageNumber" AS "firstPage"
				,		high."pdfPageNumber" AS "lastRealPage"
				,		high."pdfPageNumber"
				,		high."hdrPageNo1"
				FROM	"pdfPage" high
				JOIN	"pdfPage" low
				ON		low."fkPdfFile" = high."fkPdfFile"
				AND		low."pdfPageNumber" = high."pdfPageNumber" -1
				WHERE	high."hdrPageNo1" IS NOT NULL
				AND		low."hdrPageNo1" IS NULL
					UNION ALL
				SELECT	high."fkPdfFile"
				,		low."firstPage"
				,		CASE
							WHEN high."hdrPageNo1" IS NULL
							THEN low."lastRealPage"
							ELSE high."pdfPageNumber"
						END AS "lastRealPage"
				,		high."pdfPageNumber"
				,		low."hdrPageNo1" +1 AS "hdrPageNo1"
				FROM	"cte" low
				JOIN	"pdfPage" high
				ON		high."fkPdfFile" = low."fkPdfFile"
				AND		high."pdfPageNumber" = low."pdfPageNumber" +1
				WHERE	high."hdrPageNo1" IS NULL
				OR		high."hdrPageNo1" = low."hdrPageNo1" +1
			)
			UPDATE	pg
			SET		pg."hdrPageNo1Score" = run."pageCount"
			FROM	(	SELECT	"fkPdfFile"
						,		MIN("firstPage") AS "firstPage"
						,		"lastPage"
						,		"lastPage" - MIN("firstPage") +1 AS "pageCount"
						FROM	(	SELECT	"fkPdfFile"
									,		"firstPage"
									,		MAX("lastRealPage") AS "lastPage"
									FROM	cte
									GROUP	BY "fkPdfFile"
									,		"firstPage"
								) sub
						GROUP	BY "fkPdfFile"
						,		"lastPage"
					) run
			JOIN	"pdfPage" pg
			ON		pg."fkPdfFile" = run."fkPdfFile"
			AND		pg."pdfPageNumber" BETWEEN run."firstPage" AND run."lastPage"
			WHERE	run."lastPage" > run."firstPage"'

	SET @sql = REPLACE(@sql,'hdrPageNo1',@pageNoField)
	EXEC (@sql)

END

GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[uspSetDocumentPages]
AS
BEGIN
	SET NOCOUNT ON

	-- number the pageheaders
	UPDATE	pg
	SET		pg."docNo" = hdr."docNo"
	FROM	"pdfPage" pg
	JOIN	(	SELECT	pg."pkPdfPage"
				,		RANK() OVER (ORDER BY fl."pdfName",pg."pdfPageNumber") AS "docNo"
				FROM	"pdfPage" pg
				JOIN	"pdfFile" fl
				ON		fl."pkPDF" = pg."fkPdfFile"
				WHERE	pg."hasPageHeaders" = 'Y'
			) hdr
	ON		hdr."pkPdfPage" = pg."pkPdfPage"

	-- distribute the docNos across the other pages
	UPDATE	pg
	SET		pg."docNo" = hdr."docNo"
	FROM	"pdfPage" pg
	JOIN	"pdfPage" hdr
	ON		hdr."fkPdfFile" = pg."fkPdfFile"
	AND		hdr."pdfPageNumber" = (
				SELECT	MAX("pdfPageNumber")
				FROM	"pdfPage" pg2
				WHERE	pg2."fkPdfFile" = pg."fkPdfFile"
				AND		pg2."pdfPageNumber" < pg."pdfPageNumber"
				AND		pg2."docNo" IS NOT NULL)
	WHERE	pg."hasPageHeaders" IS NULL

	-- set the doc page numbers
	UPDATE	pg
	SET		pg."docPageNo" = hdr."docPageNo"
	FROM	"pdfPage" pg
	JOIN	(	SELECT	"pkPdfPage"
				,		RANK() OVER (PARTITION BY "docNo" ORDER BY "pdfPageNumber") AS "docPageNo"
				FROM	"pdfPage"
			) hdr
	ON		hdr."pkPdfPage" = pg."pkPdfPage"

END

GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[uspSplitPages] 
AS
BEGIN
	SET NOCOUNT ON

	UPDATE	"pdfPage"
	SET		"hasPageHeaders" = NULL
	,		"bestPageNo" = NULL
	,		"hdrPageNo1Score" = NULL
	,		"hdrPageNo2Score" = NULL
	,		"hdrPageNo3Score" = NULL
	,		"ftrPageNo1Score" = NULL
	,		"ftrPageNo2Score" = NULL
	,		"docNo" = NULL
	,		"docPageNo" = NULL
	,		"hdrPageNo1" = NULL
	,		"hdrPageNo2" = NULL
	,		"hdrPageNo3" = NULL
	,		"ftrPageNo1" = NULL
	,		"ftrPageNo2" = NULL

	UPDATE	"pdfPage"
	SET		"hasPageHeaders" = 'Y'
	WHERE	pdfPageNumber = 1

	UPDATE	pg
	SET		"hasPageHeaders" = 'Y'
	FROM	"pdfPage" pg
	JOIN	"pageHeaders" hdr
	ON		CHARINDEX(hdr."headerText", pg."pageText") BETWEEN 1 AND hdr."maxOffsetFromTop"
	AND		CHARINDEX(hdr."headerText", pg."pageText") >= hdr."minOffsetFromTop"
	LEFT	JOIN "pageHeaders" cnt
	ON		cnt."indicatesNotNewPage" = 'Y'
	AND		pg."pageText" LIKE cnt."headerText"
	WHERE	pg."processed"='1'
	AND		cnt."headerText" IS NULL
	AND		pg.pdfPageNumber NOT IN (2,3)
	AND		pg.hasPageHeaders IS NULL

	-- if we have a blank page, the following page may be a new document
	UPDATE	pg2
	SET		pg2.hasPageHeaders = 'Y'
	FROM	"pdfPage" pg1
	JOIN	"pdfPage" pg2
	ON		pg2.fkPdfFile = pg1.fkPdfFile
	AND		pg2.pdfPageNumber = pg1.pdfPageNumber +1
	WHERE	pg1.pageText IS NULL
	AND		pg2.hasPageHeaders IS NULL
	AND		pg2.pageText IS NOT NULL

	EXEC uspAnalysePageNumbers 'hdrPageNo1'
	EXEC uspAnalysePageNumbers 'hdrPageNo2'
	EXEC uspAnalysePageNumbers 'hdrPageNo3'
	EXEC uspAnalysePageNumbers 'ftrPageNo1'
	EXEC uspAnalysePageNumbers 'ftrPageNo2', 'Y'

END
GO
