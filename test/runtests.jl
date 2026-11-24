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

	@testset "Dates, points and queries of Wikidata" begin
		# Wikidata writes 490 BCE as -0489 (year 0 is 1 BCE)
		@test (HistoricalGeography.wikidata_year("-0489-09-12T00:00:00Z"), HistoricalGeography.wikidata_year("1863-07-01T00:00:00Z"),
			HistoricalGeography.wikidata_year("unknown")) == (-490, 1863, nothing)
		@test (HistoricalGeography.wikidata_point("Point(23.9667 38.1167)"), HistoricalGeography.wikidata_point("Point(1 2"),
			HistoricalGeography.wikidata_point(nothing)) == ((23.9667, 38.1167), nothing, nothing)
		@test HistoricalGeography.query_escape("wd:Q8676 é'~") == "wd%3AQ8676%20%C3%A9%27~"
	end

	@testset "Routes across the antimeridian" begin
		# from 170 E to 170 W the short way: 10 degrees to the line, 10 beyond it, the latitude halfway between
		@test HistoricalGeography.route_lines([[170.0, 10.0], [-170.0, 20.0], [-160.0, 20.0]]) ==
			[Any[[170.0, 10.0], [180.0, 15.0]], Any[[-180.0, 15.0], [-170.0, 20.0], [-160.0, 20.0]]]
		@test HistoricalGeography.route_lines([[0.0, 0.0], [10.0, 5.0]]) == [Any[[0.0, 0.0], [10.0, 5.0]]]
	end

	@testset "Places named in a Perseus text" begin
		xml = """<div type="textpart" subtype="book" n="1"><div type="textpart" subtype="chapter" n="2">
			<placeName key="tgn,7001289">Argos</placeName> and <name type="place" key="perseus,Phoenicia"><reg>Phoenicia [35.5,34.0] (Perseus)</reg>the Phoenicians</name>
			<note>a note naming <placeName key="tgn,7010720">Athens</placeName></note></div></div>"""
		mentions, located = HistoricalGeography.perseus_mentions(xml)
		@test (mentions, located) == ([(key = "tgn,7001289", name = "Argos", passage = "1.2"), (key = "perseus,Phoenicia", name = "the Phoenicians", passage = "1.2")],
			Dict("perseus,Phoenicia" => (35.5, 34.0)))
	end

	@testset "The topic data written by hand" begin
		@test HistoricalGeography.topic_names() == [:bly, :genji, :nights, :odysseus, :polo, :qin, :xuanzang, :zhenghe]
		# every event, stage and mention names a place of its file, and every place is named
		for name in HistoricalGeography.topic_names()
			data = HistoricalGeography.topic_data(name)
			items = [get(data, "events", []); get(data, "stages", []); get(data, "mentions", [])]
			named = Set(item["place"] for item in items)
			@test (name, issubset(named, keys(data["places"])), length(named) == length(data["places"]), all(item -> !isempty(item["passage"]), items)) ==
				(name, true, true, true)
		end
		@test_throws ArgumentError HistoricalGeography.topic_data(:iliad)
		@test_throws ArgumentError journey(nothing, :iliad; folder = mktempdir())
		@test_throws ArgumentError text_places(nothing, :iliad; folder = mktempdir())
		@test_throws ArgumentError battlefields(nothing, :korea; folder = mktempdir())
	end
end
