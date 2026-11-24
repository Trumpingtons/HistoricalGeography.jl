# HistoricalGeography.jl

The borders of states, the populations of the past, old maps and topic maps, read into DuckDB from Julia.

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

Old maps come in three kinds, each given as the address a web map draws it from:

- **The maps of France of IGN's Géoplateforme**: the map of Cassini (1756-1815) in two copies, the map of the état-major (1820-1866), IGN's map of 1950 and its aerial photographs of 1950 to 1995, and today's Plan IGN and photographs, as tiles. `ign_layer` gives the address of a map's tiles, its zooms and the source to name.
- **The georeferenced maps of Allmaps**: the maps that libraries, archives and museums share through IIIF and that Allmaps holds with their ground control points. `allmaps` writes those that cover a place or an area to a table, with their titles and years from their IIIF manifests, the address of their tiles warped by the Allmaps Tile Server, and the link to their georeference in the Allmaps Editor.
- **Eight famous maps of the world**, from the Tabula Peutingeriana to the Tasman map, which have no georeference: `famous_map` gives the address of the image, from its library's IIIF image server or Wikimedia Commons, its terms, and a box around the region it shows.

`save_geotiff`, with ArchGDAL.jl, saves the tiles of a map over an area as a GeoTIFF.

Topic maps put a work on the map, each event, stage or place with the words of its source:

- **The events of a war**: `war_events(con, "Q8676"; folder)` writes the battles, sieges and campaigns that Wikidata gives as parts of a war, with a place and a date, as the table `events`; `war_events(con, :qin; folder)` the conquests of Qin Shi Huang, written by hand from chapter 6 of Sima Qian's *Records of the Grand Historian*, each with its passage in Chinese and an English summary. `battlefields` writes the battlefields of the Civil War, the War of Independence or the War of 1812 as the American Battlefield Protection Program of the National Park Service drew them.
- **The stages of a journey**: `journey(con, name; folder)` writes the stages of a journey written by hand from its source, with their dates or years, passages and Wikidata items, and the route through them, split where it crosses the antimeridian: `:bly` (Nellie Bly, *Around the World in Seventy-Two Days*), `:darwin` (the voyage of HMS Beagle, from Charles Darwin's *Journal of Researches*), `:zhenghe` (the Changle and Liujiagang inscriptions of Zheng He), `:xuanzang` (the *Records of the Western Regions of the Great Tang*), `:polo` (Marco Polo in Henry Yule's translation) and `:odysseus` (the *Odyssey* in A. T. Murray's translation, each place of legend where Strabo or Thucydides put it, in their words).
- **The places a text names**: `text_places(con, :herodotus; folder)` writes the places of Herodotus' *Histories* that the Perseus Digital Library tags with the Getty Thesaurus of Geographic Names or its own gazetteer, each with the number of times it is named and the passages; `:genji` (*The Tale of Genji*, in Shibuya Eiichi's text) and `:nights` (*The Arabian Nights*, in Richard F. Burton's translation) the places written by hand from them, each with its passages.

The hand-written data are in `data/topics`, one TOML file per work, every passage as its source prints it and every place with its Wikidata item, from which its coordinates come.

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

```julia
# The map of Cassini: the address of its tiles, its zooms and the source to name
cassini = ign_layer(:cassini)
(cassini.url, cassini.minzoom, cassini.maxzoom, cassini.attribution)

# The georeferenced maps of Allmaps that cover the Louvre and at most 1,000 km², as the table maps:
# id, title, year, library, km2, tiles, image, manifest, editor, geom
allmaps(con; at = (2.3364, 48.8606), largest = 1000, folder = "data")
Tables.columntable(DBInterface.execute(con, "SELECT title, year, library FROM maps ORDER BY year NULLS LAST LIMIT 10"))

# The famous maps, and the image and terms of Mercator's map of 1569
famous_maps().title
mercator = famous_map(:mercator)
(mercator.image, mercator.terms)

# The map of Cassini around the Louvre at zoom 14, saved as a GeoTIFF
using ArchGDAL
save_geotiff(cassini.url, (2.30, 48.83, 2.39, 48.89); zoom = 14, path = "cassini-paris.tif")
```

In Pollis, the Historical Borders panel of the Historical Geography and Archaeology Toolbox draws the borders on a map with a year slider, the Historical Populations panel the cities and the grid, the Historical Maps panel an old map beside today's map, with a line to swipe between them, and the Topic Maps page the topic maps, under At War, Conquests, Places and Journeys.

## Sources

The data belong to their authors, whose terms apply: [Cliopatria](https://github.com/Seshat-Global-History-Databank/cliopatria), [historical-basemaps](https://github.com/aourednik/historical-basemaps), [CShapes 2.0](https://icr.ethz.ch/data/cshapes/), [European urban population, 700 - 2000](https://doi.org/10.17026/dans-xzy-u62q), [Historical Urban Population: 3700 BC - AD 2000](https://doi.org/10.7927/H4ZG6QBX), [HYDE 3.5](https://doi.org/10.24416/UU01-F45D44), and the maps of IGN under the [Licence Ouverte](https://www.etalab.gouv.fr/licence-ouverte-open-licence/), whose map of Cassini is cited with the source `ign_layer` gives. The maps of Allmaps and the famous maps are under the terms of the libraries that hold them, which `famous_map` gives for each famous map. The items of [Wikidata](https://www.wikidata.org) are under CC0 1.0, the texts of the [Perseus Digital Library](https://github.com/PerseusDL/canonical-greekLit) under CC BY-SA 4.0, the [Getty Thesaurus of Geographic Names](https://www.getty.edu/research/tools/vocabularies/tgn/) under the Open Data Commons Attribution License, and Shibuya Eiichi's text of *The Tale of Genji* on [Wikisource](https://ja.wikisource.org) under CC BY-SA 3.0, which the passages of `data/topics/genji.toml` share; the other texts quoted are in the public domain, as are the [battlefield boundaries](https://www.nps.gov/orgs/2287/battlefield-boundaries-map.htm) of the National Park Service.

- Bennett, J. S. and 12 coauthors (2025). Cliopatria - A geospatial database of world-wide political entities from 3400BCE to 2024CE. *Scientific Data* 12(1), 247. [doi:10.1038/s41597-025-04516-9](https://doi.org/10.1038/s41597-025-04516-9)
- Buringh, E. (2020). European urban population, 700 - 2000. DANS Data Station Social Sciences and Humanities. [doi:10.17026/dans-xzy-u62q](https://doi.org/10.17026/dans-xzy-u62q)
- Klein Goldewijk, K. (2025). HYDE data for the Global Carbon Budget (2025). Utrecht University. [doi:10.24416/UU01-F45D44](https://doi.org/10.24416/UU01-F45D44)
- Ourednik, A. (2026). Historical boundaries of world countries and cultural regions (historical-basemaps). [github.com/aourednik/historical-basemaps](https://github.com/aourednik/historical-basemaps)
- Reba, M., Reitsma, F. and Seto, K. C. (2016). Spatializing 6,000 years of global urbanization from 3700 BC to AD 2000. *Scientific Data* 3, 160034. [doi:10.1038/sdata.2016.34](https://doi.org/10.1038/sdata.2016.34)
- Schvitz, G., Girardin, L., Rüegger, S., Weidmann, N. B., Cederman, L.-E. and Gleditsch, K. S. (2022). Mapping the international system, 1886-2019: the CShapes 2.0 dataset. *Journal of Conflict Resolution* 66(1), 144-161. [doi:10.1177/00220027211013563](https://doi.org/10.1177/00220027211013563)

## License

MIT
