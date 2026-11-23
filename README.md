# HistoricalGeography.jl

The borders of states over the centuries, read into DuckDB from Julia.

- **Cliopatria** (Seshat: Global History Databank), version 0.2.1: the polities of the world from 3400 BCE to 2024, each shape with the years it held, as realms (the polities inside no other) or as their parts.
- **historical-basemaps** (André Ourednik): world maps at 37 chosen years from 100 to 2010, such as 1492, 1715, 1815, 1914 and 1945, each standing for its year until the next map.
- **CShapes 2.0** (ETH Zurich): the states and dependencies of the world from 1886 to 2019, with the date of each change of border.

Each source is downloaded once into a folder and read with DuckDB's `spatial` extension, as records of a name, the first and last year of a shape (`starts`, `ends`) and the shape (`geom`). `historical_borders` writes the borders of a source within an area and a span of years to a table, cut to the area, with their areas in square kilometres, and returns the years in which a border changes there; `borders_geojson` writes them, simplified for drawing, as GeoJSON with their years, for a map with a year slider.

The functions take a DuckDB connection with the extension `spatial` loaded and `SET geometry_always_xy = true` (longitude, latitude).

## Usage

```julia
using HistoricalGeography, DuckDB, Tables

con = DBInterface.connect(DuckDB.DB)
foreach(sql -> DBInterface.execute(con, sql), ["LOAD spatial", "SET geometry_always_xy = true"])

# The realms of Cliopatria in Europe from 1300 to 2024, as the table borders: name, starts, ends, geom, km2
b = historical_borders(con, :cliopatria; folder = "data", box = (-12, 34, 45, 72), since = 1300, upto = 2024)
println(b.source, ": ", length(b.changes), " years of change from ", b.since, " to ", b.upto)

# The states that held Bologna, in order
Tables.columntable(DBInterface.execute(con, """
	SELECT name, min(starts) AS starts, max(ends) AS ends FROM borders
	WHERE ST_Intersects(geom, ST_Point(11.3426, 44.4938)) GROUP BY name ORDER BY starts"""))

# Every shape with its years, simplified, as GeoJSON for a map with a year slider
path = borders_geojson(con)

# The world maps of historical-basemaps from 1492 to 1530, read on their own
sql = historical_basemaps(; folder = "data", since = 1492, upto = 1530)
Tables.columntable(DBInterface.execute(con, "SELECT starts, ends, count(*) AS n FROM ($(sql)) GROUP BY ALL ORDER BY starts"))
```

In Pollis, the Historical Borders panel of the Historical Geography and Archaeology Toolbox draws the borders on a map with a year slider.

## Sources

The data belong to their authors, whose terms apply: [Cliopatria](https://github.com/Seshat-Global-History-Databank/cliopatria), [historical-basemaps](https://github.com/aourednik/historical-basemaps) and [CShapes 2.0](https://icr.ethz.ch/data/cshapes/).

- Bennett, J. S. and 12 coauthors (2025). Cliopatria - A geospatial database of world-wide political entities from 3400BCE to 2024CE. *Scientific Data* 12(1), 247. [doi:10.1038/s41597-025-04516-9](https://doi.org/10.1038/s41597-025-04516-9)
- Ourednik, A. (2026). Historical boundaries of world countries and cultural regions (historical-basemaps). [github.com/aourednik/historical-basemaps](https://github.com/aourednik/historical-basemaps)
- Schvitz, G., Girardin, L., Rüegger, S., Weidmann, N. B., Cederman, L.-E. and Gleditsch, K. S. (2022). Mapping the international system, 1886-2019: the CShapes 2.0 dataset. *Journal of Conflict Resolution* 66(1), 144-161. [doi:10.1177/00220027211013563](https://doi.org/10.1177/00220027211013563)

## License

MIT
