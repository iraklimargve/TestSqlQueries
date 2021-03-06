USE [ClubBookingV1]
GO
/****** Object:  StoredProcedure [dbo].[GetBookingSettings]    Script Date: 4/23/2022 22:00:03 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		<I.M>
-- Create date: <4/13/2022>
-- Description:	<Get Booking Settings with json>
-- =============================================
ALTER PROCEDURE [dbo].[GetBookingSettings]
	@UserId INT,
	@Page INT = 0,
	@Limit INT = 0,
	@SortBy NVARCHAR(150) = '',
	@SortDir NVARCHAR(150) = '',
	@Filter NVARCHAR(255) = '',
	@TotalRowCount INT = 0 OUTPUT,
	@LocationFilter NVARCHAR(150) = '',
	@ClientId NVARCHAR(255) = NULL,
	@BookingSettings NVARCHAR(MAX) OUTPUT


AS
BEGIN
	SET NOCOUNT ON;

    DECLARE @MasterClientId NVARCHAR(255),
			@BookingSettingsId INT,
			@BookingFilterId INT,
			@Username NVARCHAR(255),
			@FirstRec INT, 
			@LastRec INT,
			@sql NVARCHAR(MAX),
			@BookingOptionsId INT,
			@TempMatrixId INT,
			@tRezultJson NVARCHAR(MAX),
			@TempLanguagesTable [BookingLocalizationLanguages],
			@TempLanguage NVARCHAR(MAX),
			@BookingAdvancedId INT,
			@Counter INT = 1,
			@tempDayName NVARCHAR(255),
			@locAvailabilityId INT,
			@MaxCount INT = 1,
			@tempRowId INT
	
	SELECT @MasterClientId = sud.MasterClientId, @Username = su.Username
	FROM [ClubspeedV9_Test].[dbo].SysUserDataAccess AS sud
	INNER JOIN [ClubspeedV9_Test].[dbo].SysUser AS su ON sud.SysUserId = su.UserId
	WHERE sud.SysUserId = @UserId

	IF (@ClientId = '')
	BEGIN
		SET @ClientId = NULL
	END

	-- Get Main List 
	IF (@ClientId IS NULL)
	BEGIN
	
		SELECT	@TotalRowCount = 0,
				@FirstRec = @Page*@Limit+1,		
				@LastRec =  @FirstRec + @limit
			
		--DROP TABLE IF EXISTS  [ClubBookingV1].[dbo].#tResult ;

		CREATE TABLE #tResult 
		(
			ClientId NVARCHAR(255),
			[Group] INT,
			[Enabled] BIT
		)

		INSERT INTO #tResult
		SELECT mx.ChildClientId, bs.[Group], bs.BookingEnabled FROM BookingSettings AS bs
		INNER JOIN AWSClubspeedCustomerMatrix AS mx ON mx.MatrixId = bs.MatrixId


		IF(LEN(@Filter) > 0)
		BEGIN 
			DELETE FROM #tResult
			WHERE ClientId NOT LIKE '%' + @Filter + '%'
		END

		SET @TotalRowCount = (SELECT COUNT(*) FROM #tResult)


		IF(LEN(@SortBy) = 0 AND LEN(@SortDir) = 0)
			BEGIN
				WITH tmpRes AS
					(
						SELECT *, ROW_NUMBER() OVER (ORDER BY ClientId ASC) AS ID FROM #tResult
					)
					SELECT ClientId, [Group], [Enabled] FROM tmpRes WHERE ID >= @FirstRec and ID < @LastRec
			END
		ELSE
			BEGIN 
			
				SET @sql = 'with tmpRes as
				(
					select *, row_number() over (order by '
			
				SET @sql = @sql + @SortBy + ' ' + @SortDir

				SET @sql = @sql +  ') as ID from #tResults )
				select ClientId, Group, Enabled from tmpRes where ID >= ' + CAST(@FirstRec AS NVARCHAR(50)) +  ' and ID < ' + CAST(@LastRec AS NVARCHAR(50))

				EXEC sp_executesql @sql
			END

		DROP TABLE #tResult
	END
	--Get Inside Tabs
	ELSE 
	BEGIN
		
		--IF NOT EXISTS
		IF NOT EXISTS  (SELECT bs.RowId FROM BookingSettings AS bs
						INNER JOIN AWSClubspeedCustomerMatrix AS mx ON mx.MatrixId = bs.MatrixId
						WHERE mx.ChildClientId = @ClientId AND mx.MasterClientId = @MasterClientId AND bs.Deleted = 0)
		BEGIN
			SELECT @TempMatrixId = MatrixId FROM AWSClubspeedCustomerMatrix
			WHERE ChildClientId = @ClientId AND MasterClientId = @MasterClientId

			INSERT INTO BookingSettings (MatrixId, BookingEnabled, Deleted, [Group])
			VALUES (@TempMatrixId, 1, 0, '')

			SET @BookingSettingsId = SCOPE_IDENTITY()
		END
		ELSE
		BEGIN
			SELECT @BookingSettingsId = RowId FROM dbo.BookingSettings AS bs
			INNER JOIN AWSClubspeedCustomerMatrix AS mx ON mx.MatrixId = bs.MatrixId
			WHERE mx.ChildClientId = @ClientId AND mx.MasterClientId = @MasterClientId AND bs.Deleted = 0
		END

		SELECT @BookingOptionsId = RowId FROM dbo.BookingOptions
		WHERE BookingSettingsId = @BookingSettingsId AND Deleted = 0


		DECLARE @termsAndConditions TABLE
		(
			[label] NVARCHAR(500),
			[text] NVARCHAR(500),
			linkTermsAndConditions BIT,
			termsAndConditionsURL NVARCHAR(500)
		)

		INSERT INTO @termsAndConditions
		SELECT [Label] AS [label], [Text] AS [text], LinkTermsAndConditions AS linkTermsAndConditions, TermsAndConditionsURL AS termsAndConditionsURL
		FROM BookingTermsAndConditions
		WHERE BookingOptionsId = @BookingOptionsId AND Deleted = 0


		-- CREATE IF NOT EXISTS

		IF ((SELECT COUNT(RowId)  FROM  BookingBranding WHERE BookingSettingsId = @BookingSettingsId AND Deleted = 0) = 0)
		BEGIN
			INSERT INTO BookingBranding (BookingSettingsId, CreatedBy, CreatedOn, Deleted)
			VALUES (@BookingSettingsId, @Username, GETDATE(), 0)
		END

		IF ((SELECT COUNT(RowId)  FROM  BookingOptions WHERE BookingSettingsId = @BookingSettingsId AND Deleted = 0) = 0)
		BEGIN
			INSERT INTO BookingOptions(BookingSettingsId, CreatedBy, CreatedOn, Deleted)
			VALUES (@BookingSettingsId, @Username, GETDATE(), 0)
		END

		IF ((SELECT COUNT(RowId)  FROM  BookingLocalization WHERE BookingSettingsId = @BookingSettingsId AND Deleted = 0) = 0)
		BEGIN
			INSERT INTO BookingLocalization(BookingSettingsId, CreatedBy, CreatedOn, Deleted)
			VALUES (@BookingSettingsId, @Username, GETDATE(), 0)
		END

		IF ((SELECT COUNT(RowId)  FROM  BookingConvenienceFees WHERE BookingSettingsId = @BookingSettingsId AND Deleted = 0) = 0)
		BEGIN
			INSERT INTO BookingConvenienceFees(BookingSettingsId, CreatedBy, CreatedOn, Deleted)
			VALUES (@BookingSettingsId, @Username, GETDATE(), 0)
		END

		IF ((SELECT COUNT(RowId)  FROM  BookingAdvanced WHERE BookingSettingsId = @BookingSettingsId AND Deleted = 0) = 0)
		BEGIN
			INSERT INTO BookingAdvanced(BookingSettingsId, CreatedBy, CreatedOn, Deleted)
			VALUES (@BookingSettingsId, @Username, GETDATE(), 0)
		END

		IF ((SELECT COUNT(RowId) FROM BookingLocationAvailability WHERE BookingSettingsId = @BookingSettingsId AND Deleted = 0) = 0)
		BEGIN
			INSERT INTO BookingLocationAvailability(BookingSettingsId, CreatedBy, CreatedOn, Deleted)
			VALUES (@BookingSettingsId, @Username, GETDATE(), 0)
		END

		IF ((SELECT COUNT(RowId) FROM BookingFilters WHERE BookingSettingsId = @BookingSettingsId AND Deleted = 0) = 0)
		BEGIN
			INSERT INTO BookingFilters (BookingSettingsId, CreatedBy, CreatedOn, Deleted)
			VALUES (@BookingSettingsId, @Username, GETDATE(), 0)
		END

		SELECT @locAvailabilityId = bla.RowId 
		FROM BookingLocationAvailability AS bla WHERE BookingSettingsId = @BookingSettingsId AND Deleted = 0

		DECLARE @tempTable TABLE
		(
			id INT IDENTITY(1, 1),
			[name] NVARCHAR(255) 
		)

		INSERT INTO @tempTable ([name])
		VALUES
		('Monday'),
		('Tuesday'),
		('Wednesday'),
		('Thursday'),
		('Friday'),
		('Saturday'),
		('Sunday')


		WHILE (@Counter <= 7)
		BEGIN
			SELECT @tempDayName = [name] FROM @tempTable WHERE id = @Counter

			IF((SELECT COUNT(RowId) FROM BookingAvailabilityPerDay
				WHERE BookingLocationAvailabilityId = @locAvailabilityId AND Deleted = 0 AND DayOfTheWeek = @tempDayName) = 0)
			BEGIN
				INSERT INTO BookingAvailabilityPerDay
				(BookingLocationAvailabilityId, DayOfTheWeek, [Start], [End], Active, CreatedBy, CreatedOn, Deleted)
				VALUES
				(@locAvailabilityId, @tempDayName, null, null, 0, @Username, GETDATE(), 0)
			END

			SET @Counter += 1
		END

		--Language

		SELECT @TempLanguage = Languages FROM BookingLocalization
		WHERE BookingSettingsId = @BookingSettingsId AND Deleted = 0

		IF (@TempLanguage = '')
		BEGIN
			SET @TempLanguage = NULL
		END

		DECLARE @TempIds TABLE(
			id INT
		)

		IF (@TempLanguage IS NOT NULL)
		BEGIN
			INSERT INTO @TempIds
			SELECT CONVERT(INT, VALUE) FROM STRING_SPLIT(@TempLanguage, ';')
		END

		INSERT INTO @TempLanguagesTable
		SELECT bl.RowId AS id, bl.LanguageName AS [name] FROM
		@TempIds AS ti
		INNER JOIN BookingLanguages AS bl ON bl.RowId = ti.id

		-- BlackoutDates

		SELECT @BookingAdvancedId = RowId FROM BookingAdvanced
		WHERE BookingSettingsId = @BookingSettingsId AND Deleted = 0

		DECLARE @blackoutDatesTable TABLE
		(
			unavailableFrom DATETIME NULL,
			unavailableUntil DATETIME NULL,
			[repeat] INT NULL,
			[repeatName] NVARCHAR(500) NULL
		)

		INSERT INTO @blackoutDatesTable
		SELECT bbod.UnavailableFrom AS 'unavailableFrom', bbod.UnavailableUntil AS 'unavailableUntil', bbod.[RepeatId] AS 'repeat', bbodr.RepeatName AS 'repeatName'
		FROM BookingBlackOutDates AS bbod
		INNER JOIN BookingBlackOutDateRepeats AS bbodr ON bbodr.RowId = bbod.RepeatId
		WHERE BookingAdvancedId = @BookingAdvancedId AND Deleted = 0

		IF ((SELECT COUNT(*) FROM @blackoutDatesTable) = 0)
		BEGIN
			INSERT INTO @blackoutDatesTable (unavailableFrom, unavailableUntil, [repeat], [repeatName])
			VALUES (null, null, null, null)
		END

		-- Location Availability Start

		DECLARE @availabilityPerDay TABLE 
		(
			dayOfTheWeek NVARCHAR(255) NULL,
			[start] VARCHAR(255) NULL,
			[end] VARCHAR(255) NULL,
			active BIT NULL
		)

		INSERT INTO @availabilityPerDay
		SELECT bap.DayOfTheWeek, bap.[Start], bap.[End], bap.Active
		FROM BookingAvailabilityPerDay AS bap
		WHERE bap.BookingLocationAvailabilityId = @locAvailabilityId AND bap.Deleted = 0

		-- Filters 

		SELECT @BookingFilterId = RowId FROM dbo.BookingFilters
		WHERE BookingSettingsId = @BookingSettingsId AND Deleted = 0

		DECLARE @activityTypeIds TABLE
		(
			id INT IDENTITY(1, 1),
			activityTypeId INT
		)

		INSERT INTO @activityTypeIds
		SELECT ActivityTypeID
		FROM ActivityType
		WHERE ClientId = @ClientId

		SET @MaxCount = (SELECT COUNT(*) FROM @activityTypeIds)
		SET @Counter = 1

		DECLARE @TempActivityId INT

		WHILE (@Counter <= @MaxCount)
		BEGIN
			SELECT @TempActivityId = activityTypeId FROM @activityTypeIds WHERE id = @Counter
			
			IF ((SELECT COUNT(*) FROM BookingActivityTypes WHERE ActivityTypeId = @TempActivityId) = 0)
			BEGIN
				INSERT INTO BookingActivityTypes 
				(BookingFiltersId, ClientId, ActivityTypeId, TypeEnabled, CreatedOn, Deleted)
				VALUES
				(@BookingFilterId, @ClientId, @TempActivityId, 0, GETDATE(), 0)
			END

			SET @Counter += 1
		END

		DECLARE @activityTypeFilters TABLE
		(
			[name] NVARCHAR(500) NULL,
			[enabled] BIT NOT NULL DEFAULT 0
		)

		INSERT INTO @activityTypeFilters
		SELECT act.ActivityDescription, bt.TypeEnabled
		FROM BookingActivityTypes AS bt
		INNER JOIN ActivityType AS act ON act.ActivityTypeID = bt.ActivityTypeId
		INNER JOIN BookingFilters AS bf ON bf.RowId = bt.BookingFiltersId
		WHERE bt.BookingFiltersId = @BookingFilterId AND bt.Deleted = 0 AND bf.Deleted = 0 
				AND bf.BookingSettingsId = @BookingSettingsId AND act.ClientId = @ClientId

		DECLARE @customFilters TABLE
		(
			[index] INT IDENTITY(1, 1),
			rowId INT NULL,
			filterName NVARCHAR(500) NULL,
			filterQuestion NVARCHAR(500) NULL
		)

		INSERT INTO @customFilters
		SELECT bcf.RowId, bcf.FilterName, bcf.FilterQuestion
		FROM BookingCustomFilters AS bcf
		INNER JOIN BookingFilters AS bf ON bcf.BookingFiltersId = bf.RowId
		WHERE bf.BookingSettingsId = @BookingSettingsId AND bf.Deleted = 0 AND bcf.Deleted = 0

		DECLARE @subCustomFilters TABLE
		(
			[index] INT NULL,
			[filter] NVARCHAR(500) NULL,
			display BIT NULL
		)

		SET @Counter = 1
		SET @MaxCount = (SELECT COUNT(*) FROM @customFilters)

		WHILE (@Counter <= @MaxCount)
		BEGIN
			SELECT @tempRowId = rowId FROM @customFilters WHERE [index] = @Counter
		
			INSERT INTO @subCustomFilters
			SELECT @Counter, FilterName, FilterDisplay
			FROM BookingSubCustomFilters
			WHERE BookingCustomFiltersId = @tempRowId AND Deleted = 0

			IF ((SELECT COUNT(*) FROM @subCustomFilters WHERE [index] = @Counter) = 0)
			BEGIN
				INSERT INTO @subCustomFilters ([index], [filter], [display]) VALUES (@Counter, null, 0)
			END

			SET @Counter += 1

		END

		IF ((SELECT COUNT(*) FROM @customFilters) = 0)
		BEGIN 
			INSERT INTO @customFilters (filterName, filterQuestion) VALUES (null, null)
			INSERT INTO @subCustomFilters ([index], [filter], [display]) VALUES (1, null, 0)
		END

		DECLARE @guestSegmentation TABLE
		(
			[order] INT NULL,
			[name] NVARCHAR(500) NULL,
			[description] NVARCHAR(500) NULL,
			display BIT NULL
		)

		INSERT INTO @guestSegmentation
		SELECT bgs.[Order], bgs.[Name], bgs.[Description], bgs.Display
		FROM BookingGuestSegmentation AS bgs
		INNER JOIN BookingFilters AS bf ON bf.RowId = bgs.BookingFiltersId
		WHERE bf.BookingSettingsId = @BookingSettingsId AND bf.Deleted = 0 AND bgs.Deleted = 0

		IF ((SELECT COUNT(*) FROM @guestSegmentation) = 0)
		BEGIN
			INSERT INTO @guestSegmentation ([order], [name], [description], display)
			VALUES (1, null, null, 0)
		END

		-- Json

		SET @tRezultJson = 
			(SELECT  
					 --Branding
					 b.Logo as 'branding.logo',
					 b.Favicon as 'branding.favicon', 
					 b.CompanyUrl as 'branding.companyUrl', 
					 b.WebPageTitle as 'branding.webPageTitle', 
					 b.Address as 'branding.address', 
					 b.City as 'branding.city', 
					 b.State as 'branding.state',
					 b.PostalCode as 'branding.postalCode', 
					 b.Phone as 'branding.phone', 
					 b.OperatingHours as 'branding.operatingHours', 
					 b.PrimaryColor as 'branding.primaryColor', 
					 b.CustomCSS as 'branding.customCSS',
					 --BookingOptions
					 bo.ReservationTimer as 'bookingOptions.reservationTimer',
					 bo.EnableClubBooking as 'bookingOptions.enableClubBooking',
					 bo.EnableLeadCaptureFlow as 'bookingOptions.enableLeadCaptureFlow',
					 bo.Domain as 'bookingOptions.domain',
					 bo.EnablePayOnSite as 'bookingOptions.enablePayOnSite',
					 bo.LeadCaptureRecepientEmail as 'bookingOptions.leadCaptureRecepientEmail',
					 (SELECT [label], [text], linkTermsAndConditions, termsAndConditionsURL FROM @termsAndConditions FOR JSON AUTO, INCLUDE_NULL_VALUES) AS 'bookingOptions.termsAndConditions',
					-- Filters
					 JSON_QUERY(
						CASE
							WHEN (SELECT COUNT(*) FROM @activityTypeFilters) = 0
							THEN '[]'
							ELSE
								(SELECT [name], [enabled] FROM @activityTypeFilters FOR JSON AUTO, INCLUDE_NULL_VALUES)
							END)
					 AS 'filters.activityTypeFilters',
					 (SELECT [index], [filterName], [filterQuestion] FROM @customFilters FOR JSON AUTO, INCLUDE_NULL_VALUES) AS 'filters.customFilters',
					 (SELECT [index], [filter], [display] FROM @subCustomFilters FOR JSON AUTO, INCLUDE_NULL_VALUES) AS 'filters.customFiltersFilters',
					 (SELECT [order], [name], [description], display FROM @guestSegmentation FOR JSON AUTO, INCLUDE_NULL_VALUES) AS 'filters.guestSegmentation',
					 --localization
					 c.RowId AS 'localization.currency.id',
					 c.CurrencyName AS 'localization.currency.name',
					 df.RowId AS 'localization.dateFormatting.id',
					 df.DateFormatName AS 'localization.dateFormatting.name',
					 nf.RowId AS 'localization.numberFormatting.id',
					 nf.NumberFormatName AS 'localization.numberFormatting.name',
					 (SELECT id, [name] FROM @TempLanguagesTable FOR JSON AUTO, INCLUDE_NULL_VALUES) AS 'localization.clubBookingLanguages',
					 [time].RowId AS 'localization.timezone.id',
					 [time].TimezoneName AS 'localization.timezone.name',
					 -- Location Availability
					 bla.HoursStart AS 'locationAvailability.start',
					 bla.HoursEnd AS 'locationAvailability.end',
					 (SELECT [start], [end], active FROM @availabilityPerDay WHERE dayOfTheWeek = 'Monday' FOR JSON AUTO, INCLUDE_NULL_VALUES) AS 'locationAvailability.availabilityPerDay.monday',
					 (SELECT [start], [end], active FROM @availabilityPerDay WHERE dayOfTheWeek = 'Tuesday' FOR JSON AUTO, INCLUDE_NULL_VALUES) AS 'locationAvailability.availabilityPerDay.tuesday',
					 (SELECT [start], [end], active FROM @availabilityPerDay WHERE dayOfTheWeek = 'Wednesday' FOR JSON AUTO, INCLUDE_NULL_VALUES) AS 'locationAvailability.availabilityPerDay.wednesday',
					 (SELECT [start], [end], active FROM @availabilityPerDay WHERE dayOfTheWeek = 'Thursday' FOR JSON AUTO, INCLUDE_NULL_VALUES) AS 'locationAvailability.availabilityPerDay.thursday',
					 (SELECT [start], [end], active FROM @availabilityPerDay WHERE dayOfTheWeek = 'Friday' FOR JSON AUTO, INCLUDE_NULL_VALUES) AS 'locationAvailability.availabilityPerDay.friday',
					 (SELECT [start], [end], active FROM @availabilityPerDay WHERE dayOfTheWeek = 'Saturday' FOR JSON AUTO, INCLUDE_NULL_VALUES) AS 'locationAvailability.availabilityPerDay.saturday',
					 (SELECT [start], [end], active FROM @availabilityPerDay WHERE dayOfTheWeek = 'Sunday' FOR JSON AUTO, INCLUDE_NULL_VALUES) AS 'locationAvailability.availabilityPerDay.sunday',
					 --BookingConvenienceFees
					 bcf.EnableClubspeedConvenienceFee AS 'convenienceFees.clubspeed.enableConvenienceFee',
					 bcf.ClubspeedFeeType AS 'convenienceFees.clubspeed.feeType.id',
					 bcft.FeeTypeName AS 'convenienceFees.clubspeed.feeType.name',
					 bcf.ClubspeedFeeAmount AS 'convenienceFees.clubspeed.feeAmount',
					 bcf.ClubspeedMinFeeAmount AS 'convenienceFees.clubspeed.minimumFeeAmount',
					 bcf.ClubspeedMaxFeeAmount AS 'convenienceFees.clubspeed.maximumFeeAmount',
					 bcf.ClubspeedFeePayor AS 'convenienceFees.clubspeed.convenienceFeePayor.id',
					 bcfp.FeePayerName AS 'convenienceFees.clubspeed.convenienceFeePayor.name',
					 bcf.EnableVenueConvenienceFee AS 'convenienceFees.venue.enableConvenienceFee',
					 bcf.VenueFeeType AS 'convenienceFees.venue.feeType.id',
					 vft.FeeTypeName AS 'convenienceFees.venue.feeType.name',
					 bcf.VenueFeeAmount AS 'convenienceFees.venue.feeAmount',
					 bcf.VenueMinFeeAmount AS 'convenienceFees.venue.minimumFeeAmount',
					 bcf.VenueMaxFeeAmount AS 'convenienceFees.venue.maximumFeeAmount',
					 bcf.VenueFeePayor AS 'convenienceFees.venue.convenienceFeePayor.id',
					 vfp.FeePayerName AS 'convenienceFees.venue.convenienceFeePayor.name',
					 --BookingAdvanced
					 (SELECT unavailableFrom, unavailableUntil AS until, JSON_QUERY((SELECT [repeat] AS id, repeatName AS [name] FROM @blackoutDatesTable FOR JSON AUTO, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES)) AS 'repeat' FROM @blackoutDatesTable FOR JSON AUTO, INCLUDE_NULL_VALUES) AS 'advanced.blackoutDates',
					 ba.SchedulingMinTime AS 'advanced.minimumTimeBetweenActivities',
					 ba.SchedulingMaxTime AS 'advanced.maximumTimeBetweenActivities',
					 ba.[Buffer] AS 'advanced.buffer',
					 ba.BookingWindowMinTime AS 'advanced.minimumTimeToBookInAdvance',
					 ba.BookingWindowMaxTime AS 'advanced.maximumTimeToBookInAdvance'


			FROM BookingBranding AS b
			LEFT JOIN BookingOptions AS bo ON bo.BookingSettingsId = @BookingSettingsId AND bo.Deleted = 0
			LEFT JOIN BookingLocalization AS bl ON bl.BookingSettingsId = @BookingSettingsId AND bl.Deleted = 0
			LEFT JOIN BookingTimezones AS [time] ON bl.Timezone = [time].RowId
			LEFT JOIN BookingDateFormats AS df ON bl.DateFormatting = df.RowId
			LEFT JOIN BookingNumberFormats AS nf ON bl.NumberFormatting = nf.RowId
			LEFT JOIN BookingCurrency AS c ON bl.Currency = c.RowId
			LEFT JOIN BookingConvenienceFees AS bcf ON bcf.BookingSettingsId = @BookingSettingsId AND bcf.Deleted = 0
			LEFT JOIN BookingAdvanced AS ba ON ba.BookingSettingsId = @BookingSettingsId AND ba.Deleted = 0
			LEFT JOIN BookingConvenienceFeeTypes AS bcft ON bcft.RowId = bcf.ClubspeedFeeType
			LEFT JOIN BookingConvenienceFeePayers AS bcfp ON bcfp.RowId = bcf.ClubspeedFeePayor
			LEFT JOIN BookingConvenienceFeeTypes AS vft ON vft.RowId = bcf.VenueFeeType
			LEFT JOIN BookingConvenienceFeePayers AS vfp ON vfp.RowId = bcf.VenueFeePayor
			LEFT JOIN BookingLocationAvailability AS bla ON bla.BookingSettingsId = @BookingSettingsId AND bla.Deleted = 0
			WHERE b.BookingSettingsId = @BookingSettingsId AND b.Deleted = 0
			FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
		)
		SET @BookingSettings = @tRezultJson

	END

END





