# HistoricalGeography.jl

The borders of states and the populations of the past, read into DuckDB from Julia.

- **Cliopatria** (Seshat: Global History Databank), version 0.2.1: the polities of the world from 3400 BCE to 2024, each shape with the years it held, as realms (the polities inside no other) or as their parts.
- **historical-basemaps** (André Ourednik): world maps at 37 chosen years from 100 to 2010, such as 1492, 1715, 1815, 1914 and 1945, each standing for its year until the next map.
- **CShapes 2.0** (ETH Zurich): the states and dependencies of the world from 1886 to 2019, with the date of each change of border.

Each source is downloaded once into a folder and read with DuckDB's `spatial` extension, as records of a name, the first and last year of a shape (`starts`, `ends`) and the shape (`geom`). `historical_borders` writes the borders of a source within an area and a span of years to a table, cut to the area, with their areas in square kilometres, and returns the years in which a border changes there. `place_history` gives the states that held a place, in order, and `area_change` the area of each state in two years. `borders_geojson` writes the borders, simplified for drawing, as GeoJSON with their years, for a map with a year slider.

The functions take a DuckDB connection with the extension `spatial` loaded and `SET geometry_always_xy = true` (longitude, latitude).

The populations of the past come from three sources, each written as a table of values by year:

- **European urban population, 700 - 2000** (Eltjo Buringh): the inhabitants of 2,262 European settlements at 19 years from 700 to 2000, each value marked imputed, proxied or neither.
- **Historical Urban Population: 3700 BC - AD 2000** (Reba, Reitsma and Seto): the cities of Chandler and Modelski, geolocated, with the certainty of each location, downloaded from NASA's Earthdata with an account of Earthdata Login (`ENV["EARTHDATA_USERNAME"]` and `ENV["EARTHDATA_PASSWORD"]`, or `ENV["EARTHDATA_TOKEN"]`).
- **HYDE 3.5** (Kees Klein Goldewijk): the population of the world on a grid of 5 arc-minutes from 10,000 BCE to 2025, read from `population.nc` with ArchGDAL.jl. Utrecht University's server answers only web browsers, so the file (640 MB) is downloaded in a browser from its link, which `hyde_file` prints, and put in the folder.

`city_populations` writes the cities of a source within an area and a span of years to a table, and `hyde_population` the people of HYDE 3.5 in cells of a chosen size. `cities_geojson` and `grid_geojson` write them as GeoJSON with their years, for a map with a year slider, coloured by classes of size or of people per km². `largest_cities`, `city_history`, `cell_history` and `total_population` answer questions of those tables.

## Usage

```julia
using HistoricalGeography, DuckDB, Tables

con = DBInterface.connect(DuckDB.DB)
foreach(sql -> DBInterface.execute(con, sql), ["LOAD spatial", "SET geometry_always_xy = true"])

# The realms of Cliopatria in Europe from 1300 to 2024, as the table borders: name, starts, ends, geom, km2
b = historical_borders(con, :cliopatria; folder = "data", box = (-12, 34, 45, 72), since = 1300, upto = 2024)
println(b.source, ": ", length(b.changes), " years of change from ", b.since, " to ", b.upto)

# The states that held Bologna, in order
place_history(con, 11.3426, 44.4938)

# The area of each state in 1500 and 1914, the largest changes first
area_change(con, 1500, 1914; limit = 10)

# Every shape with its years, simplified, as GeoJSON for a map with a year slider
path = borders_geojson(con)

# The world maps of historical-basemaps from 1492 to 1530, read on their own
sql = historical_basemaps(; folder = "data", since = 1492, upto = 1530)
Tables.columntable(DBInterface.execute(con, "SELECT starts, ends, count(*) AS n FROM ($(sql)) GROUP BY ALL ORDER BY starts"))
```

```julia
using ArchGDAL  # for HYDE 3.5
DBInterface.execute(con, "LOAD excel")  # for Historical Urban Population

# Buringh's cities in Europe from 1000 to 2000, as the table cities: key, name, country, lon, lat, year, population, note
p = city_populations(con, :buringh; folder = "data", box = (-12, 34, 45, 72), since = 1000, upto = 2000)
largest_cities(con, 1500; limit = 10)   # the largest cities of 1500, each with the year of its value
city_history(con, 11.3426, 44.4938)     # every value of the city nearest Bologna
points = cities_geojson(con; least = 10_000)  # each value as a point with its years, for a map with a year slider

# HYDE 3.5 in Europe from 1000 to 2000 in cells of 0.5 degrees, as the table grid: lon, lat, year, population, km2
g = hyde_population(con; folder = "data", box = (-12, 34, 45, 72), since = 1000, upto = 2000, cell = 0.5)
total_population(con; table = "grid")   # the people of the box at each year of HYDE
```

In Pollis, the Historical Borders panel of the Historical Geography and Archaeology Toolbox draws the borders on a map with a year slider, and the Historical Populations panel the cities and the grid.

## Sources

The data belong to their authors, whose terms apply: [Cliopatria](https://github.com/Seshat-Global-History-Databank/cliopatria), [historical-basemaps](https://github.com/aourednik/historical-basemaps), [CShapes 2.0](https://icr.ethz.ch/data/cshapes/), [European urban population, 700 - 2000](https://doi.org/10.17026/dans-xzy-u62q), [Historical Urban Population: 3700 BC - AD 2000](https://doi.org/10.7927/H4ZG6QBX) and [HYDE 3.5](https://doi.org/10.24416/UU01-F45D44).

- Bennett, J. S. and 12 coauthors (2025). Cliopatria - A geospatial database of world-wide political entities from 3400BCE to 2024CE. *Scientific Data* 12(1), 247. [doi:10.1038/s41597-025-04516-9](https://doi.org/10.1038/s41597-025-04516-9)
- Buringh, E. (2020). European urban population, 700 - 2000. DANS Data Station Social Sciences and Humanities. [doi:10.17026/dans-xzy-u62q](https://doi.org/10.17026/dans-xzy-u62q)
- Klein Goldewijk, K. (2025). HYDE data for the Global Carbon Budget (2025). Utrecht University. [doi:10.24416/UU01-F45D44](https://doi.org/10.24416/UU01-F45D44)
- Ourednik, A. (2026). Historical boundaries of world countries and cultural regions (historical-basemaps). [github.com/aourednik/historical-basemaps](https://github.com/aourednik/historical-basemaps)
- Reba, M., Reitsma, F. and Seto, K. C. (2016). Spatializing 6,000 years of global urbanization from 3700 BC to AD 2000. *Scientific Data* 3, 160034. [doi:10.1038/sdata.2016.34](https://doi.org/10.1038/sdata.2016.34)
- Schvitz, G., Girardin, L., Rüegger, S., Weidmann, N. B., Cederman, L.-E. and Gleditsch, K. S. (2022). Mapping the international system, 1886-2019: the CShapes 2.0 dataset. *Journal of Conflict Resolution* 66(1), 144-161. [doi:10.1177/00220027211013563](https://doi.org/10.1177/00220027211013563)

## License

MIT
