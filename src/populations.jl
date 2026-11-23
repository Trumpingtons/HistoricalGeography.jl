const REBA = "Historical Urban Population"
const REBA_URL = "https://data.earthdata.nasa.gov/nasa-earth/human-dimensions/sedac-root/downloads/data/urbanspatial/urbanspatial-hist-urban-pop-3700bc-ad2000/urbanspatial-hist-urban-pop-3700bc-ad2000-xlsx.xlsx"

"""
	reba_cities(; folder)

The SQL that reads Historical Urban Population: 3700 BC - AD 2000 (Reba, Reitsma and Seto), the cities of Chandler
and Modelski geolocated, as records `key`, `name`, `country`, `lon`, `lat`, `year`, `population` and `note`, the
certainty of the place: 1 where it is sure, 2 and 3 where less so. Where the two sources give a city two values for
one year, the record has the larger.

The spreadsheet (0.8 MB) is downloaded once into `folder` from NASA's Earthdata, with an account of Earthdata Login
([`earthdata_token`](@ref)); it is read with DuckDB's `excel` extension, which must be loaded.
"""
function reba_cities(; folder::AbstractString)
	path = earthdata_file(REBA_URL, joinpath(folder, "urbanspatial-hist-urban-pop-3700bc-ad2000.xlsx"))
	return """SELECT cityid AS key, any_value(City) AS name, any_value(Country) AS country, any_value(Longitude::DOUBLE) AS lon,
		any_value(Latitude::DOUBLE) AS lat, year::INTEGER AS year, max(pop::DOUBLE) AS population, 'certainty ' || max(Certainty) AS note
	FROM read_xlsx('$(quoted(path))', sheet = 'Historical Urban Population', header = true, all_varchar = true)
	WHERE TRY_CAST(pop AS DOUBLE) > 0 GROUP BY cityid, year::INTEGER"""
end

const BURINGH = "European Urban Population"

"""
	buringh_cities(; folder)

The SQL that reads European urban population, 700 - 2000 (Buringh), the inhabitants of 2,262 European settlements
at 19 years from 700 to 2000, as records `key`, `name`, `country`, `lon`, `lat`, `year`, `population` and `note`,
which says whether the value is imputed or proxied, and is empty where it is neither. A settlement without
inhabitants in a year, written 0, has no record for it. The table (4.9 MB) is downloaded once into `folder` from DANS.
"""
function buringh_cities(; folder::AbstractString)
	path = kept("https://ssh.datastations.nl/api/access/datafile/20415", joinpath(folder, "buringh-european-urban-population-700-2000.tab"))
	return """SELECT city || ', ' || country || ' (' || latitudeindegrees || ' ' || longitudeindegrees || ')' AS key, city AS name, country, replace(longitudeindegrees, ',', '.')::DOUBLE AS lon,
		replace(latitudeindegrees, ',', '.')::DOUBLE AS lat, year::DOUBLE::INTEGER AS year, "inhabitantsin000-s"::DOUBLE * 1000 AS population, natureofestimate AS note
	FROM read_csv('$(quoted(path))', delim = '\t', header = true, quote = '"', all_varchar = true)
	WHERE TRY_CAST("inhabitantsin000-s" AS DOUBLE) > 0"""
end

"""The cities' sources, by their names in [`city_populations`](@ref)."""
const CITY_SOURCES = Dict(:reba => (REBA, reba_cities), :buringh => (BURINGH, buringh_cities))

"""
	city_populations(con, source; folder, box = (-180, -90, 180, 90), since = nothing, upto = nothing, table = "cities")

The populations of the cities of `source` within `box` (west, south, east, north, in degrees) between the years
`since` and `upto` (by default, all the years of the source), written to the table `table` of `con` with the
columns `key` (one per city), `name`, `country`, `lon`, `lat`, `year`, `population` and `note`.

`source` is `:reba` ([`reba_cities`](@ref), which needs an account of NASA's Earthdata and DuckDB's `excel`
extension) or `:buringh` ([`buringh_cities`](@ref)); its files are downloaded once into `folder`.

Returns `(; source, since, upto, cities, years)`: the name of the source, the first and last years with a value, the
number of cities, and the years with values, in order.
"""
function city_populations(con, source::Symbol; folder::AbstractString, box = (-180, -90, 180, 90),
		since::Union{Integer, Nothing} = nothing, upto::Union{Integer, Nothing} = nothing, table::AbstractString = "cities")
	haskey(CITY_SOURCES, source) || throw(ArgumentError("source is :reba or :buringh, not :$(source)"))
	length(box) == 4 || throw(ArgumentError("box is (west, south, east, north), in degrees"))
	since === nothing || upto === nothing || since <= upto || throw(ArgumentError("since ($(since)) comes after upto ($(upto))"))
	name, records = CITY_SOURCES[source]
	west, south, east, north = Float64.(box)
	DBInterface.execute(con, """CREATE OR REPLACE TABLE "$(table)" AS SELECT * FROM ($(records(; folder)))
		WHERE lon BETWEEN $(west) AND $(east) AND lat BETWEEN $(south) AND $(north)
		$(since === nothing ? "" : "AND year >= $(since)") $(upto === nothing ? "" : "AND year <= $(upto)")""")
	years = Int.(rows(con, """SELECT DISTINCT year FROM "$(table)" ORDER BY year""").year)
	isempty(years) && error("$(name) has no cities in this box$(since === nothing ? "" : " from $(since)")$(upto === nothing ? "" : " until $(upto)")")
	cities = Int(rows(con, """SELECT count(DISTINCT key) AS n FROM "$(table)" """).n[1])
	return (; source = name, since = first(years), upto = last(years), cities, years)
end

"""
	cities_geojson(con; table = "cities", every = nothing, least = 0, reach = 100,
		classes = [10_000, 20_000, 50_000, 100_000, 200_000, 500_000, 1_000_000], path = tempname() * ".geojson")

The cities of `table` (made by [`city_populations`](@ref)) as GeoJSON points written to `path`, which is returned,
each with the city's `name`, `country`, `population` and `note`, and the years in which it is shown, `starts` and
`ends`. `class` is the number of the class of `classes` the population is in (0 below the first value), and `size`
the class as text, for a map whose colours follow the classes rather than the population, which spans several
orders of magnitude.

Without `every`, there is a point for each value, shown from its year until the year before the city's next value,
for `reach` years at most, so that a value is not carried across a gap of centuries in the source; a city's last
value is shown in its own year only. With `every`, a number of years, there is a point at each year divisible by
`every`, from a city's first value to its last, with its latest value up to that year if it is less than `reach`
years old, shown for `every` years: fewer points, for a source with values in many years. A point whose population is below `least` is
left out, so that a city shows from the time it reaches `least`.
"""
function cities_geojson(con; table::AbstractString = "cities", every::Union{Integer, Nothing} = nothing, least::Real = 0, reach::Integer = 100,
		classes::AbstractVector{<:Real} = [10_000, 20_000, 50_000, 100_000, 200_000, 500_000, 1_000_000], path::AbstractString = tempname() * ".geojson")
	every === nothing || every > 0 || throw(ArgumentError("every is a positive number of years"))
	bounds, names = class_lists(classes)
	points = every === nothing ?
		"""SELECT name, country, population, note, year AS starts,
			least(coalesce(lead(year) OVER (PARTITION BY key ORDER BY year) - 1, year), year + $(reach) - 1) AS ends, lon, lat FROM "$(table)" """ :
		"""WITH spans AS (SELECT key, min(year) AS first, max(year) AS last FROM "$(table)" GROUP BY key),
			steps AS (SELECT unnest(range(ceil(min(first) / $(every))::INTEGER * $(every), max(last) + 1, $(every))) AS step FROM spans),
			shown AS (SELECT s.key, t.step, s.last FROM spans s JOIN steps t ON t.step BETWEEN s.first AND s.last)
		SELECT c.name, c.country, c.population, c.note, w.step AS starts, least(w.step + $(every) - 1, w.last) AS ends, c.lon, c.lat
		FROM shown w ASOF JOIN "$(table)" c ON c.key = w.key AND c.year <= w.step WHERE w.step - c.year < $(reach)"""
	DBInterface.execute(con, """COPY (SELECT name, country, round(population)::BIGINT AS population, note,
			len(list_filter($(bounds), lambda b: b <= population)) AS class, $(names)[len(list_filter($(bounds), lambda b: b <= population)) + 1] AS size,
			starts, ends, ST_Point(lon, lat) AS geom FROM ($(points)) WHERE population >= $(Float64(least)))
		TO '$(quoted(path))' (FORMAT GDAL, DRIVER 'GeoJSON', LAYER_CREATION_OPTIONS 'COORDINATE_PRECISION=4')""")
	return path
end

"""The SQL lists of the lower bounds of `classes` and of the names of the classes, below the first, between two, and from the last."""
function class_lists(classes::AbstractVector{<:Real})
	issorted(classes) && !isempty(classes) || throw(ArgumentError("classes are rising numbers"))
	written(v) = replace(string(round(Int, v)), r"(?<=\d)(?=(\d{3})+$)" => ",")
	labels = ["below $(written(classes[1]))"; ["$(written(classes[i])) to $(written(classes[i + 1]))" for i in 1:length(classes) - 1]; "$(written(classes[end])) and more"]
	return "[$(join(Float64.(classes), ", "))]", "[$(join(("'" .* quoted.(labels) .* "'"), ", "))]"
end

const HYDE = "HYDE 3.5"
const HYDE_LINK = "https://geo.public.data.uu.nl/vault-hyde/hyde35_c9_apr2025%5B1749214444%5D/original/gbc2025_7apr_base/NetCDF/population.nc"

"""
	hyde_file(; folder)

The path of `population.nc` of HYDE 3.5 (Klein Goldewijk), the population of the world on a grid of 5 arc-minutes
from 10,000 BCE to 2025, in `folder`. Utrecht University's server answers only web browsers, so the file (640 MB) is
downloaded in a browser from its link, $(HYDE_LINK), and put in `folder`; until then the function stops and says so.
"""
function hyde_file(; folder::AbstractString)
	path = joinpath(folder, "population.nc")
	isfile(path) || error("""HYDE 3.5's population.nc is not in $(folder). Open its link in a web browser, which downloads it (640 MB):
		$(HYDE_LINK)
		then put population.nc in $(folder) and run again.""")
	return path
end

"""
	hyde_population(con; folder, box = (-12, 34, 45, 72), since = nothing, upto = nothing, cell = 0.5, table = "grid")

The population of HYDE 3.5 ([`hyde_file`](@ref)) within `box` (west, south, east, north, in degrees) at each of
its years between `since` and `upto`, summed over cells of `cell` degrees, written to the table `table` of `con`
with the columns `lon` and `lat` (the centre of the cell), `year`, `population` and `km2` (the area of the cell). A
cell without people in a year has no row for it. HYDE has a grid every 1,000 years from 10,000 BCE, every 100 years
from 0 to 1700, every 10 years to 1950 and every year from then to 2025.

Needs ArchGDAL.jl loaded (`using ArchGDAL`), which reads the NetCDF file. Returns `(; source, since, upto, years,
cell)`: the name of the source, the first and last years with people, the years of the grids, and the size of a cell.
"""
function hyde_population(con; kwargs...)
	ext = Base.get_extension(@__MODULE__, :HistoricalGeographyHydeExt)
	ext === nothing && error("hyde_population reads HYDE's NetCDF file with ArchGDAL.jl: run `using ArchGDAL` first")
	return ext.population_grid(con; kwargs...)
end

"""
	grid_geojson(con; table = "grid", classes = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000], path = tempname() * ".geojson")

The cells of `table` (made by [`hyde_population`](@ref)) as GeoJSON squares written to `path`, which is returned,
by their people per km² in classes that start at the values of `classes`: `class` is the number of the class (0
below the first value), `people_km2` the class as text, and `starts` and `ends` the years in which the cell stays
in it. Each grid stands for its year until the year before the next grid, so that a cell is one square for each run
of years in one class, which keeps the file small.
"""
function grid_geojson(con; table::AbstractString = "grid", classes::AbstractVector{<:Real} = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000],
		path::AbstractString = tempname() * ".geojson")
	bounds, names = class_lists(classes)
	half = rows(con, """SELECT (max(lon) - min(lon)) / greatest(count(DISTINCT lon) - 1, 1) / 2 AS h FROM "$(table)" """).h[1]
	DBInterface.execute(con, """COPY (
		WITH years AS (SELECT year, coalesce(lead(year) OVER (ORDER BY year) - 1, year) AS until FROM (SELECT DISTINCT year FROM "$(table)")),
		cells AS (SELECT DISTINCT lon, lat FROM "$(table)"),
		filled AS (SELECT c.lon, c.lat, y.year, y.until, coalesce(g.population, 0) AS population,
				len(list_filter($(bounds), lambda b: b <= coalesce(g.population / g.km2, 0))) AS class
			FROM cells c CROSS JOIN years y LEFT JOIN "$(table)" g ON g.lon = c.lon AND g.lat = c.lat AND g.year = y.year),
		runs AS (SELECT *, sum(fresh) OVER (PARTITION BY lon, lat ORDER BY year) AS run FROM (
			SELECT *, CASE WHEN class = lag(class) OVER (PARTITION BY lon, lat ORDER BY year) THEN 0 ELSE 1 END AS fresh FROM filled))
		SELECT class, $(names)[class + 1] AS people_km2, min(year) AS starts, max(until) AS ends,
			ST_MakeEnvelope(lon - $(half), lat - $(half), lon + $(half), lat + $(half)) AS geom
		FROM runs GROUP BY lon, lat, run, class HAVING max(population) > 0
	) TO '$(quoted(path))' (FORMAT GDAL, DRIVER 'GeoJSON', LAYER_CREATION_OPTIONS 'COORDINATE_PRECISION=4')""")
	return path
end

"""
	largest_cities(con, year; table = "cities", reach = 100, limit = nothing)

The cities of `table` (made by [`city_populations`](@ref)) in `year`, from the largest, as columns `name`,
`country`, `population` and `valued`, the year of the value: a city's latest value up to `year`, if it is less than
`reach` years old, for a city whose values start at or before `year` and end at or after it. At most `limit` rows.
"""
function largest_cities(con, year::Integer; table::AbstractString = "cities", reach::Integer = 100, limit::Union{Integer, Nothing} = nothing)
	return rows(con, """WITH spans AS (SELECT key, $(year) AS step FROM "$(table)" GROUP BY key HAVING min(year) <= $(year) AND max(year) >= $(year))
		SELECT c.name, c.country, round(c.population)::BIGINT AS population, c.year AS valued
		FROM spans s ASOF JOIN "$(table)" c ON c.key = s.key AND c.year <= s.step WHERE s.step - c.year < $(reach)
		ORDER BY c.population DESC, c.name $(limit === nothing ? "" : "LIMIT $(Int(limit))")""")
end

"""
	city_history(con, lon, lat; table = "cities")

The values of the city of `table` (made by [`city_populations`](@ref)) nearest the point `lon`, `lat`, in order, as
columns `name`, `country`, `year`, `population`, `note` and `km`, its distance from the point in kilometres.
"""
function city_history(con, lon::Real, lat::Real; table::AbstractString = "cities")
	point = "ST_Point($(Float64(lon)), $(Float64(lat)))"
	return rows(con, """WITH nearest AS (SELECT key, ST_Distance_Sphere(ST_Point(lon, lat), $(point)) / 1000 AS km FROM "$(table)"
			GROUP BY key, lon, lat ORDER BY km LIMIT 1)
		SELECT c.name, c.country, c.year, round(c.population)::BIGINT AS population, c.note, round(n.km, 1) AS km
		FROM "$(table)" c JOIN nearest n USING (key) ORDER BY c.year""")
end

"""
	cell_history(con, lon, lat; table = "grid")

The people of the cell of `table` (made by [`hyde_population`](@ref)) that holds the point `lon`, `lat`, at each
year of the grid, as columns `year`, `population` and `people_km2`; a year in which the cell has no people has 0.
"""
function cell_history(con, lon::Real, lat::Real; table::AbstractString = "grid")
	return rows(con, """WITH half AS (SELECT (max(lon) - min(lon)) / greatest(count(DISTINCT lon) - 1, 1) / 2 AS h FROM "$(table)"),
		cell AS (SELECT DISTINCT g.lon, g.lat FROM "$(table)" g, half WHERE abs(g.lon - $(Float64(lon))) <= h AND abs(g.lat - $(Float64(lat))) <= h LIMIT 1)
		SELECT y.year, round(coalesce(g.population, 0))::BIGINT AS population, round(coalesce(g.population / g.km2, 0), 1) AS people_km2
		FROM (SELECT DISTINCT year FROM "$(table)") y CROSS JOIN cell c LEFT JOIN "$(table)" g ON g.lon = c.lon AND g.lat = c.lat AND g.year = y.year
		ORDER BY y.year""")
end

"""
	total_population(con; table = "cities", reach = 100)

The total population of `table` at each of its years, as columns `year`, `population` and `places`, the number of
cities or cells counted. For a table of cities ([`city_populations`](@ref)), a city counts in a year between its
first and last values, with its latest value up to that year if it is less than `reach` years old; for a grid
([`hyde_population`](@ref)), every cell with people in that year counts.
"""
function total_population(con; table::AbstractString = "cities", reach::Integer = 100)
	columns = rows(con, """SELECT column_name FROM information_schema.columns WHERE table_name = '$(quoted(table))'""").column_name
	"key" in columns || return rows(con, """SELECT year, round(sum(population))::BIGINT AS population, count(*) AS places
		FROM "$(table)" WHERE population > 0 GROUP BY year ORDER BY year""")
	return rows(con, """WITH t AS (SELECT key AS place, year, population FROM "$(table)"),
		spans AS (SELECT place, min(year) AS first, max(year) AS last FROM t GROUP BY place),
		steps AS (SELECT DISTINCT year AS step FROM t),
		shown AS (SELECT s.place, p.step FROM spans s JOIN steps p ON p.step BETWEEN s.first AND s.last)
		SELECT w.step AS year, round(sum(t.population))::BIGINT AS population, count(*) AS places
		FROM shown w ASOF JOIN t ON t.place = w.place AND t.year <= w.step WHERE w.step - t.year < $(reach) GROUP BY w.step ORDER BY w.step""")
end
