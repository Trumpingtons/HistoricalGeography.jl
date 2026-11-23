"""
    HistoricalGeography

The borders of states over the centuries, read into DuckDB from Julia: the polities of Cliopatria (Seshat: Global
History Databank) from 3400 BCE to 2024, the world maps of historical-basemaps at 37 chosen years from 100 to 2010,
and the states and dependencies of CShapes 2.0 from 1886 to 2019. Each source is downloaded once into a folder and
read with DuckDB's `spatial` extension, as records of a name, the first and last year of a shape, and the shape.

The populations of the past come from HYDE 3.5 (a grid of the world's population from 10,000 BCE to 2025), the
cities of Chandler and Modelski as Reba, Reitsma and Seto geolocated them (3700 BC to AD 2000, from NASA's Earthdata),
and Buringh's European urban population (700 to 2000), each written as a table of values by year, and as GeoJSON
for a map with a year slider.

The functions take a DuckDB connection with the extension `spatial` loaded and `SET geometry_always_xy = true`
(longitude, latitude); they write tables in it, or return the SQL that reads what they downloaded.
"""
module HistoricalGeography

using DBInterface, Downloads, Tables
using Base64: base64encode

# The sources, as SQL of their records: name, starts, ends, geom
export cliopatria, historical_basemaps, basemap_years, cshapes
# The borders of a source in an area, year by year
export historical_borders, borders_geojson
# Questions to the table of borders
export place_history, area_change
# The populations of cities and of the cells of a grid, year by year
export reba_cities, buringh_cities, city_populations, cities_geojson
export hyde_file, hyde_population, grid_geojson
# Questions to the tables of populations
export largest_cities, city_history, cell_history, total_population
# NASA's Earthdata
export earthdata_token

const AGENT = "User-Agent" => "HistoricalGeography.jl (https://pollis.org)"

"""The text of an SQL string literal: each `'` doubled."""
quoted(text::AbstractString) = replace(text, "'" => "''")

rows(con, sql) = Tables.columntable(DBInterface.execute(con, sql))

"""
	kept(url, path; headers)

The file at `url`, downloaded once to `path` and read from there afterwards. A download that fails is tried again
four times, 5, 10, 20 and 40 seconds apart, unless the server refuses the request (HTTP 4xx other than 429).
"""
function kept(url::AbstractString, path::AbstractString; headers = Pair{String, String}[])
	isfile(path) && return path
	mkpath(dirname(path))
	for k in 0:4
		try
			Downloads.download(url, path * ".part"; headers = [AGENT; headers])
			return mv(path * ".part", path; force = true)
		catch e
			status = e isa Downloads.RequestError ? e.response.status : 0
			(k == 4 || 400 <= status < 500 && status != 429) && rethrow()
			@info "The download of $(basename(path)) failed (HTTP $(status)): trying again in $(5 * 2^k) s"
			sleep(5 * 2^k)
		end
	end
end

include("sources.jl")
include("borders.jl")
include("earthdata.jl")
include("populations.jl")

end
