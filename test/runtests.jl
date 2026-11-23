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

	@testset "The maps of France of IGN" begin
		cassini = ign_layer(:cassini)
		@test (cassini.minzoom, cassini.maxzoom, cassini.years) == (6, 14, "1756-1815")
		@test cassini.url == "https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=BNF-IGNF_GEOGRAPHICALGRIDSYSTEMS.CASSINI" *
			"&STYLE=normal&TILEMATRIXSET=PM_6_14&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/png"
		# IGN's terms ask the maps of Cassini to name the copy whose sheets were scanned
		@test (occursin("BIBLIOTHEQUE NATIONALE DE FRANCE", cassini.attribution), occursin("Archives nationales", ign_layer(:cassini_king).attribution),
			ign_layer(:plan).attribution) == (true, true, "IGN, Géoplateforme")
		@test length(ign_layers().id) == 10
		@test_throws ArgumentError ign_layer(:scan25)
	end

	@testset "Titles and years of IIIF manifests" begin
		@test HistoricalGeography.label_text(Dict("fr" => ["Plan de Paris"], "none" => ["x"])) in ("Plan de Paris", "x")
		@test HistoricalGeography.label_text(Dict("en" => String[], "nl" => ["Kaart van Leiden"])) == "Kaart van Leiden"
		@test HistoricalGeography.label_text([Dict("@value" => " Plan of London ", "@language" => "en")]) == "Plan of London"
		@test HistoricalGeography.label_text(nothing) == ""
		@test HistoricalGeography.manifest_year(Dict("navDate" => "1739-01-01T00:00:00Z")) == 1739
		dated = Dict("metadata" => [Dict("label" => Dict("en" => ["Scale"]), "value" => Dict("en" => ["1:5000, 1860"])),
			Dict("label" => Dict("en" => ["Date"]), "value" => Dict("none" => ["circa 1777"]))])
		@test HistoricalGeography.manifest_year(dated) == 1777
		@test ismissing(HistoricalGeography.manifest_year(Dict("metadata" => [Dict("label" => "Title", "value" => "Bologna 1702")])))
	end

	@testset "Allmaps and the famous maps" begin
		@test_throws ArgumentError allmaps(nothing; folder = mktempdir())  # neither at nor box, before any download
		@test_throws ArgumentError allmaps(nothing; at = (2.35, 48.86, 0), folder = mktempdir())
		maps = famous_maps()
		@test (length(maps.id), all(maps.west .< maps.east), all(maps.south .< maps.north)) == (8, true, true)
		mercator = famous_map(:mercator)
		@test (mercator.year, mercator.library) == (1569, "Universitätsbibliothek Basel")
		@test_throws ArgumentError famous_map(:piri_reis)
	end

	@testset "Names written into SQL" begin
		@test HistoricalGeography.quoted("Jacques' maps/x.geojson") == "Jacques'' maps/x.geojson"
	end
end
