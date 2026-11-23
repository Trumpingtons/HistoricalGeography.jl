const CLIOPATRIA = "Cliopatria 0.2.1"
const CLIOPATRIA_URL = "https://github.com/Seshat-Global-History-Databank/cliopatria/raw/v0.2.1/cliopatria.geojson.zip"

"""
	cliopatria(; folder, units = :realms)

The SQL that reads the polities of Cliopatria 0.2.1 (Seshat: Global History Databank), from 3400 BCE (written
`-3400`) to 2024, as records `name`, `starts`, `ends` (the first and last year of each shape) and `geom`. The archive
(46 MB) is downloaded once into `folder`.

`units` chooses the level of the polities:

- `:realms`: the polities inside no other, each kingdom, empire or other state once, as a whole;
- `:parts`: the members Cliopatria places inside them, without the wholes.

Cliopatria writes the name of a whole in parentheses, `(Ottoman Empire)`; the records give it without them.
"""
function cliopatria(; folder::AbstractString, units::Symbol = :realms)
	units in (:realms, :parts) || throw(ArgumentError("units is :realms or :parts, not :$(units)"))
	archive = kept(CLIOPATRIA_URL, joinpath(folder, "cliopatria-0.2.1.geojson.zip"))
	level = units == :realms ? "coalesce(MemberOf, '') = ''" : "Name NOT LIKE '(%'"
	return """SELECT CASE WHEN Name LIKE '(%' THEN substr(Name, 2, length(Name) - 2) ELSE Name END AS name, FromYear AS starts, ToYear AS ends, geom
	FROM ST_Read('/vsizip/$(quoted(archive))/cliopatria_polities_only_v021.geojson') WHERE Type = 'POLITY' AND $(level)"""
end

const BASEMAPS = "Historical Basemaps"
# the version of 2 November 2026
const BASEMAPS_COMMIT = "4b5039e50d8d2464b065bd76ad6086cd4597108d"
const BASEMAP_YEARS = [100:100:1200; 1279; 1300; 1400; 1492; 1500; 1530; 1600; 1650; 1700; 1715; 1783; 1800; 1815; 1878; 1880;
	1900; 1914; 1920; 1930; 1938; 1945; 1960; 1994; 2000; 2010]

"""
	basemap_years()

The years of the world maps of historical-basemaps that [`historical_basemaps`](@ref) reads: 100, 200, … 1200,
then 1279, 1300, 1400, 1492, 1500, 1530, 1600, 1650, 1700, 1715, 1783, 1800, 1815, 1878, 1880, 1900, 1914, 1920,
1930, 1938, 1945, 1960, 1994, 2000 and 2010.
"""
basemap_years() = copy(BASEMAP_YEARS)

"""The maps of historical-basemaps that cover `since` to `upto`, each as the years it stands for: its own year until the year before the next map."""
function basemap_spans(since::Integer, upto::Integer)
	spans = [(y, i < length(BASEMAP_YEARS) ? BASEMAP_YEARS[i + 1] - 1 : y) for (i, y) in enumerate(BASEMAP_YEARS)]
	wanted = [span for span in spans if span[1] <= upto && span[2] >= since]
	isempty(wanted) && throw(ArgumentError("$(BASEMAPS) has maps from $(first(BASEMAP_YEARS)) to $(last(BASEMAP_YEARS)), none between $(since) and $(upto)"))
	return wanted
end

"""
	historical_basemaps(; folder, since = 100, upto = 2010)

The SQL that reads the world maps of historical-basemaps (André Ourednik) at the years of [`basemap_years`](@ref)
between `since` and `upto`, as records `name`, `starts`, `ends` and `geom`. Each map stands for its own year until
the year before the next map, so `starts` is the year of the map and `ends` the year before the next one; the last
map, of 2010, stands for 2010 only.

The maps are read at the version of 2 November 2026 of the repository, each downloaded once into `folder`.
"""
function historical_basemaps(; folder::AbstractString, since::Integer = first(BASEMAP_YEARS), upto::Integer = last(BASEMAP_YEARS))
	wanted = basemap_spans(since, upto)
	paths = [kept("https://raw.githubusercontent.com/aourednik/historical-basemaps/$(BASEMAPS_COMMIT)/geojson/world_$(a).geojson",
		joinpath(folder, "historical-basemaps-$(first(BASEMAPS_COMMIT, 7))-$(a).geojson")) for (a, _) in wanted]
	return join(["SELECT NAME AS name, $(a) AS starts, $(b) AS ends, geom FROM ST_Read('$(quoted(path))') WHERE NAME IS NOT NULL"
		for ((a, b), path) in zip(wanted, paths)], " UNION ALL ")
end

const CSHAPES = "CShapes 2.0"

"""
	cshapes(; folder)

The SQL that reads the states and dependencies of CShapes 2.0 (Schvitz, Girardin, Rüegger, Weidmann, Cederman and
Gleditsch), from 1886 to 2019, as records `name`, `starts`, `ends` and `geom`. A year holds the borders in force on
31 December: a shape that ends before then ends the year before. The file (25 MB) is downloaded once into `folder`.
"""
function cshapes(; folder::AbstractString)
	path = kept("https://icr.ethz.ch/data/cshapes/CShapes-2.0.geojson", joinpath(folder, "CShapes-2.0.geojson"))
	return """SELECT cntry_name AS name, gwsyear AS starts, CASE WHEN gwemonth = 12 AND gweday = 31 THEN gweyear ELSE gweyear - 1 END AS ends, geom
	FROM ST_Read('$(quoted(path))')"""
end
