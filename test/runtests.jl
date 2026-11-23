using HistoricalGeography, Test

@testset "HistoricalGeography" begin
	@testset "The maps of historical-basemaps" begin
		years = basemap_years()
		@test (length(years), first(years), last(years), issorted(years)) == (37, 100, 2010, true)
		# each map stands for its year until the year before the next: 1492 until 1499, 1500 until 1529, 2010 alone
		@test HistoricalGeography.basemap_spans(1495, 1530) == [(1492, 1499), (1500, 1529), (1530, 1599)]
		@test HistoricalGeography.basemap_spans(2005, 2024) == [(2000, 2009), (2010, 2010)]
		@test_throws ArgumentError HistoricalGeography.basemap_spans(-500, 50)
		@test_throws ArgumentError historical_basemaps(; folder = mktempdir(), since = 2011, upto = 2024)  # before any download
	end

	@testset "Requests refused before any download" begin
		@test_throws ArgumentError cliopatria(; folder = mktempdir(), units = :provinces)
		@test_throws ArgumentError historical_borders(nothing, :seshat; folder = mktempdir())
		@test_throws ArgumentError historical_borders(nothing, :cshapes; folder = mktempdir(), box = (0, 0, 1))
		@test_throws ArgumentError historical_borders(nothing, :cshapes; folder = mktempdir(), since = 1950, upto = 1900)
	end

	@testset "Names written into SQL" begin
		@test HistoricalGeography.quoted("Jacques' maps/x.geojson") == "Jacques'' maps/x.geojson"
	end
end
