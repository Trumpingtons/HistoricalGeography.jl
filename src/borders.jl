"""The first and last years of each source."""
const SPANS = Dict(:cliopatria => (-3400, 2024), :basemaps => (first(BASEMAP_YEARS), last(BASEMAP_YEARS)), :cshapes => (1886, 2019))

"""
	historical_borders(con, source; folder, box = (-180, -90, 180, 90), since, upto, units = :realms, table = "borders")

The borders of `source` within `box` (west, south, east, north, in degrees) between the years `since` and `upto`,
written to the table `table` of `con` with the columns `name`, `starts`, `ends`, `geom` (the shape cut to the box)
and `km2` (its area in the box, in square kilometres, on the spheroid).

`source` is `:cliopatria` ([`cliopatria`](@ref), with its `units`), `:basemaps` ([`historical_basemaps`](@ref)) or
`:cshapes` ([`cshapes`](@ref)); its files are downloaded once into `folder`. `since` and `upto` default to the first
and last years of the source. A shape's years are cut to `since` and `upto`.

Returns `(; source, since, upto, changes)`: the name of the source, the first and last years with borders in the box,
and the years in which a border changes there (the first year, and each year a shape starts or follows one that
ended), in order. Between two of them the map stays the same.
"""
function historical_borders(con, source::Symbol; folder::AbstractString, box = (-180, -90, 180, 90),
		since::Union{Integer, Nothing} = nothing, upto::Union{Integer, Nothing} = nothing, units::Symbol = :realms,
		table::AbstractString = "borders")
	haskey(SPANS, source) || throw(ArgumentError("source is :cliopatria, :basemaps or :cshapes, not :$(source)"))
	length(box) == 4 || throw(ArgumentError("box is (west, south, east, north), in degrees"))
	since = something(since, SPANS[source][1])
	upto = something(upto, SPANS[source][2])
	since <= upto || throw(ArgumentError("since ($(since)) comes after upto ($(upto))"))
	name, records = source == :cliopatria ? (CLIOPATRIA, cliopatria(; folder, units)) :
		source == :basemaps ? (BASEMAPS, historical_basemaps(; folder, since, upto)) : (CSHAPES, cshapes(; folder))
	west, south, east, north = Float64.(box)
	area = "ST_MakeEnvelope($(west), $(south), $(east), $(north))"
	DBInterface.execute(con, """CREATE OR REPLACE TABLE "$(table)" AS SELECT *, ST_Area_Spheroid(geom) / 1e6 AS km2 FROM (
		SELECT name, greatest(starts, $(since)) AS starts, least(ends, $(upto)) AS ends, ST_CollectionExtract(ST_Intersection(ST_MakeValid(geom), $(area)), 3) AS geom
		FROM ($(records)) WHERE ends >= starts AND starts <= $(upto) AND ends >= $(since) AND ST_Intersects(ST_MakeValid(geom), $(area))
	) WHERE NOT ST_IsEmpty(geom)""")
	span = rows(con, """SELECT min(starts) AS low, max(ends) AS high FROM "$(table)" """)
	span.low[1] === missing && error("$(name) has no borders in this box between $(since) and $(upto)")
	since, upto = Int(span.low[1]), Int(span.high[1])
	changes = Int.(rows(con, """SELECT y FROM (SELECT starts AS y FROM "$(table)" UNION SELECT ends + 1 FROM "$(table)" WHERE ends < $(upto)) ORDER BY y""").y)
	return (; source = name, since, upto, changes)
end

"""
	borders_geojson(con; table = "borders", tolerance = 0.02, path = tempname() * ".geojson")

The shapes of `table` (made by [`historical_borders`](@ref)), each with its `name`, `starts` and `ends`, written as
GeoJSON to `path`, which is returned. The shapes are simplified for drawing: lines straightened within `tolerance`
degrees, keeping the borders that neighbours share, and coordinates rounded to half of it; a shape left empty is
dropped.
"""
function borders_geojson(con; table::AbstractString = "borders", tolerance::Real = 0.02, path::AbstractString = tempname() * ".geojson")
	DBInterface.execute(con, """COPY (SELECT * FROM (SELECT name, starts, ends,
		ST_CollectionExtract(ST_MakeValid(ST_ReducePrecision(ST_SimplifyPreserveTopology(geom, $(Float64(tolerance))), $(tolerance / 2))), 3) AS geom FROM "$(table)") WHERE NOT ST_IsEmpty(geom))
		TO '$(quoted(path))' (FORMAT GDAL, DRIVER 'GeoJSON')""")
	return path
end
