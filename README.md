# HistoricalGeography.jl

The borders of states, the populations of the past, old maps, topic maps and the written sources of the past, read into DuckDB and Julia.

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

- **The events of a war**: `war_events(con, "Q8676"; folder)` writes the battles, sieges and campaigns that Wikidata gives as parts of a war, with a place and a date, as the table `events`, or of several wars together, for a war with a part that Wikidata does not give as one: `war_events(con, ["Q1238338", "Q9377266"]; folder)`, Caesar's Civil War with the Alexandrian War. An event Wikidata gives as both a battle and a war is a battle, and items Wikidata dates wrong are corrected by hand in `data/wikidata-corrections.toml`, each with its source. `war_events(con, :qin; folder)` the conquests of Qin Shi Huang, written by hand from chapter 6 of Sima Qian's *Records of the Grand Historian*, each with its passage in Chinese and an English summary, and `war_events(con, :samudragupta; folder)` the conquests of Samudragupta, from his pillar inscription at Allahabad in John Faithfull Fleet's translation, which gives no years. `battlefields` writes the battlefields of the Civil War, the War of Independence or the War of 1812 as the American Battlefield Protection Program of the National Park Service drew them.
- **The stages of a journey**: `journey(con, name; folder)` writes the stages of a journey written by hand from its source, with their dates or years, passages and Wikidata items, and the route through them, split where it crosses the antimeridian: `:bly` (Nellie Bly, *Around the World in Seventy-Two Days*), `:darwin` (the voyage of HMS Beagle, from Charles Darwin's *Journal of Researches*), `:humboldt` (Alexander von Humboldt and Aimé Bonpland in the Americas, from Humboldt's *Personal Narrative*, *Views of Nature*, *Researches* and *Political Essay on the Kingdom of New Spain*), `:burckhardt` (the journeys of John Lewis Burckhardt to Petra, Nubia and the Hedjaz from 1812 to 1815, each a part with a line of its own, from his *Travels in Syria and the Holy Land*, *Travels in Nubia* and *Travels in Arabia*), `:petrie` (the excavations of Flinders Petrie from 1880 to 1891, site by site, from his *Ten Years' Digging in Egypt*), `:amundsen` (the North West Passage of Roald Amundsen in the Gjøa, 1903 to 1906, each of the voyage to King Point, the journey to Eagle City and the voyage to Nome a part with a line of its own, from his *The North West Passage*), `:magellan` (the voyage of Ferdinand Magellan round the world, 1519 to 1522, from Antonio Pigafetta's relation in James Alexander Robertson's translation, *Magellan's Voyage Around the World*), `:columbus` (the four voyages of Christopher Columbus, 1492 to 1504, each a part with a line of its own, from his letters and Dr. Chanca's in R. H. Major's *Select Letters of Christopher Columbus*, with Major's introduction where they are silent), `:faxian` (the journey of the monk Faxian from Chang'an to India and Ceylon and home by sea, 399 to 414, from his *Record of Buddhistic Kingdoms* in James Legge's translation, with approximate years), `:nikitin` (Afanasy Nikitin's *Journey Beyond Three Seas*, from Tver to India and back, in Count Wielhorsky's translation in *India in the Fifteenth Century*), `:peter` (the Grand Embassy of Peter the Great to Western Europe in 1697 and 1698, in the words of Eugene Schuyler's *Peter the Great, Emperor of Russia*, since Peter wrote no account of it), `:stark` (the travels of Freya Stark in Syria, Persia and the Hadhramaut from 1927 to 1935, each journey a part with a line of its own, in short quotations of her *Letters from Syria*, *The Valleys of the Assassins* and *The Southern Gates of Arabia*), `:vangogh` (the last years of Vincent van Gogh, from Paris in 1886 to Auvers-sur-Oise in 1890, each stage with a passage of his letters in the language he wrote it in, as Jo van Gogh-Bonger printed them in *Brieven aan zijn broeder*, an English summary, and a painting of that place and time, whose image at Wikimedia Commons is the column `image`), `:zhenghe` (the Changle and Liujiagang inscriptions of Zheng He), `:xuanzang` (the *Records of the Western Regions of the Great Tang*), `:polo` (Marco Polo in Henry Yule's translation) and `:odysseus` (the *Odyssey* in A. T. Murray's translation, each place of legend where Strabo or Thucydides put it, in their words).
- **The places a text names**: `text_places(con, :herodotus; folder)` writes the places of Herodotus' *Histories* that the Perseus Digital Library tags with the Getty Thesaurus of Geographic Names or its own gazetteer, each with the number of times it is named and the passages; `:genji` (*The Tale of Genji*, in Shibuya Eiichi's text), `:nights` (*The Arabian Nights*, in Richard F. Burton's translation), `:periplus` (*The Periplus of the Erythraean Sea*, in Wilfred H. Schoff's translation) `:meghaduta` (Kalidasa's *Cloud-Messenger*, in Arthur W. Ryder's translation) and `:decameron` (Boccaccio's *Decameron*, in John Payne's translation, each place in the frame story, the stories or both, two of them with a painting of their story) the places written by hand from them, each with its passages.

The hand-written data are in `data/topics`, one TOML file per work, every passage as its source prints it and every place with its Wikidata item, from which its coordinates come.

The written sources of the past are each downloaded once into a folder and read as a table, a row per record: a vector of named tuples, or a named tuple of them for a source of more than one table, or, for a source read with DuckDB, a table of the connection given, whose number of rows is returned.

- **Paleography**: the manuscripts of a library of e-codices from their IIIF manifests, each with how to quote it, and their images, saved whole into a folder to be read without a connection (`ecodices_libraries`, `ecodices_library`, `ecodices`, `ecodices_image`, `ecodices_pages`, `ecodices_save`, `ecodices_saved`, `ecodices_copies`, `ecodices_copy_pages`); the abbreviations of Cappelli's *Lexicon Abbreviaturarum* (`cappelli`, `cappelli_image`); the catalogue of HTR-United (`htr_united`); the lines of a manuscript of CATMuS Medieval (`catmus_files`, `catmus`, `catmus_image`); the scripts and dates of CLaMM (`clamm`, `clamm_image`); the layout of the pages of DIVA-HisDB (`divahisdb`); the Hebrew pages and lines of BiblIA (`biblia`); the pages of Muharaf (`muharaf`); and the hiragana of Kuzushiji-49 (`kuzushiji`, `kuzushiji_image`).
- **Papyrology**: the databases of papyri.info, the DDbDP, the HGV, the DCLP, APIS, the APD and the Bibliographie Papyrologique (`ddbdp`, `hgv`, `dclp`, `apis`, `apd`, `bibliographie_papyrologique`); the Demotic sentences of the Thesaurus Linguae Aegyptiae (`tla_demotic`); the samples of the Vesuvius Challenge (`vesuvius`); and the data sets of Greek letters on papyri of ICDAR 2023, of Hell-Date and of the Zenon papyri (`icdar2023`, `helldate`, `zenon`).
- **Epigraphy**: the EDH, LIST, the EDR, the IRT, I.Sicily, the IIP and the USEP (`edh`, `list_inscriptions`, `edr`, `irt`, `isicily`, `iip`, `usep`); the cuneiform texts of the CDLI and of a project of ORACC, with its glossary (`cdli`, `oracc`); the German Inscriptions Online (`dio`); and the runic inscriptions of Rundata (`rundata`).

The records of TEI and EpiDoc files give their text as written, its abbreviations expanded, without the regularised spellings and the editors' corrections. `tally` and `tallied` count the values of a column, `century` gives the century of a year, and `findspots_geojson` writes the places of records with coordinates, each with its number of records, as GeoJSON for a map.

The texts of antique books, newspaper archives and encyclopedias are found by a query of words, downloaded once into a folder where they can be, and read as text:

- **Antique books**: the works of EEBO-TCP, ECCO-TCP and Evans-TCP in the catalogue of the Text Creation Partnership, and their texts from its repositories on GitHub (`tcp_catalogue`, `tcp_works`, `tcp_texts`); the texts of the Deutsches Textarchiv, a package for each part and century, and its catalogue (`dta_download`, `dta_works`); the books of Project Gutenberg, from its catalogue and the mirror of PGLAF (`gutenberg_catalogue`, `gutenberg_books`, `gutenberg_texts`); and the pages of a Wikisource, with the year of each work from Wikidata (`wikisource_search`, `wikisource_years`, `wikisource_text`).
- **Newspaper archives**: the articles of Delpher (`delpher_query`, `delpher_count`, `delpher_periods`, `delpher_articles`, `delpher_text`), of Papers Past through the DigitalNZ API (`paperspast_search`, `paperspast_articles`), the pages of Digi (`digi_search`, `digi_pages`, `digi_text`), the issues of Europeana's newspapers (`europeana_count`, `europeana_periods`, `europeana_issues`, `europeana_pages`), and the articles of American Stories, read from its archives of a year each on Hugging Face (`americanstories_download`, `americanstories_articles`).
- **Encyclopedias**: the chapters of Pliny's *Naturalis Historia* in English and Latin from the Perseus Digital Library (`pliny_chapters`), the sections of Isidore's *Etymologiae* from LacusCurtius (`isidore_sections`), the pages of the Yongle Encyclopedia on Chinese Wikisource (`yongle_search`, `yongle_texts`), the entries of Chambers's *Cyclopaedia* (1728) from the Internet Archive (`chambers_entries`), the articles of the *Encyclopédie* from ARTFL (`encyclopedie_search`, `encyclopedie_article`), and the articles of the fourth edition of *Meyers Konversations-Lexikon* (1885–1890) and of the *Brockhaus and Efron Encyclopedic Dictionary* (1890–1907) on German and Russian Wikisource (`meyers_search`, `meyers_volumes`, `meyers_text`, `brockhaus_search`, `brockhaus_text`), and those of the first edition of the *Great Soviet Encyclopedia* (1926–1947) that Russian Wikisource has (`soviet_encyclopedia_search`, `soviet_encyclopedia_text`); each with a page to read a part in a browser (`pliny_page`, `isidore_page`, `yongle_page`, `encyclopedie_page`).

`text_query` reads a query of words, joined by AND, OR and NOT, with brackets, phrases in quotes and a `*` for any ending, as a test of a text whose patterns mark the words; for the books of the 16th to 18th centuries, u and v, i and j, and s and the long s are the same letter. `query_hits` counts the words in a text, `period_counts` and `print_bars` draw counts by year or decade as bars, `ranked` numbers rows in an order, `reading_page` writes a text as a page with its words marked, and `save_texts` saves texts, a file each, with the table of their rows.

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

```julia
# The abbreviations of Cappelli's Lexicon as the table cappelli, read with DuckDB's extension excel
cappelli(con; folder = "data")
abbreviations = Tables.rowtable(DBInterface.execute(con, "SELECT * FROM cappelli"))
tallied((a.transcription for a in abbreviations); top = 10)   # the most abbreviated words

# The inscriptions of I.Sicily, and their findspots as GeoJSON
inscriptions = isicily(; folder = "data")
tallied(i.language for i in inscriptions)
path = findspots_geojson(inscriptions; name = :place, fallback = :modern_place)

# The texts of the Royal Inscriptions of the Neo-Assyrian Period in ORACC, and the glossary of their words
texts, glossary = oracc("rinap"; folder = "data")
```

In Pollis, the Historical Borders panel of the Historical Geography and Archaeology Toolbox draws the borders on a map with a year slider, the Historical Populations panel the cities and the grid, the Historical Maps panel an old map beside today's map, with a line to swipe between them, the Topic Maps page the topic maps, under At War, Conquests, Places and Journeys, and the Paleography, Papyrology and Epigraphy panels the written sources, each with what it covers, its period, size, access and licence.

## Sources

The data belong to their authors, whose terms apply: [Cliopatria](https://github.com/Seshat-Global-History-Databank/cliopatria), [historical-basemaps](https://github.com/aourednik/historical-basemaps), [CShapes 2.0](https://icr.ethz.ch/data/cshapes/), [European urban population, 700 - 2000](https://doi.org/10.17026/dans-xzy-u62q), [Historical Urban Population: 3700 BC - AD 2000](https://doi.org/10.7927/H4ZG6QBX), [HYDE 3.5](https://doi.org/10.24416/UU01-F45D44), and the maps of IGN under the [Licence Ouverte](https://www.etalab.gouv.fr/licence-ouverte-open-licence/), whose map of Cassini is cited with the source `ign_layer` gives. The maps of Allmaps and the famous maps are under the terms of the libraries that hold them, which `famous_map` gives for each famous map. The items of [Wikidata](https://www.wikidata.org) are under CC0 1.0, the texts of the [Perseus Digital Library](https://github.com/PerseusDL/canonical-greekLit) under CC BY-SA 4.0, the [Getty Thesaurus of Geographic Names](https://www.getty.edu/research/tools/vocabularies/tgn/) under the Open Data Commons Attribution License, and Shibuya Eiichi's text of *The Tale of Genji* on [Wikisource](https://ja.wikisource.org) under CC BY-SA 3.0, which the passages of `data/topics/genji.toml` share; the passages of `data/topics/stark.toml` are short quotations of the books of Freya Stark, whose copyright is her estate's; the images of the paintings of `data/topics/vangogh.toml` are Wikimedia Commons' reproductions of paintings in the public domain; the sources of paleography, papyrology and epigraphy are under the terms of their makers, from public domain and CC0 to licences that forbid commercial use, which the panels of Pollis give for each; the other texts quoted are in the public domain, as are the [battlefield boundaries](https://www.nps.gov/orgs/2287/battlefield-boundaries-map.htm) of the National Park Service.

- Bennett, J. S. and 12 coauthors (2025). Cliopatria - A geospatial database of world-wide political entities from 3400BCE to 2024CE. *Scientific Data* 12(1), 247. [doi:10.1038/s41597-025-04516-9](https://doi.org/10.1038/s41597-025-04516-9)
- Buringh, E. (2020). European urban population, 700 - 2000. DANS Data Station Social Sciences and Humanities. [doi:10.17026/dans-xzy-u62q](https://doi.org/10.17026/dans-xzy-u62q)
- Klein Goldewijk, K. (2025). HYDE data for the Global Carbon Budget (2025). Utrecht University. [doi:10.24416/UU01-F45D44](https://doi.org/10.24416/UU01-F45D44)
- Ourednik, A. (2026). Historical boundaries of world countries and cultural regions (historical-basemaps). [github.com/aourednik/historical-basemaps](https://github.com/aourednik/historical-basemaps)
- Reba, M., Reitsma, F. and Seto, K. C. (2016). Spatializing 6,000 years of global urbanization from 3700 BC to AD 2000. *Scientific Data* 3, 160034. [doi:10.1038/sdata.2016.34](https://doi.org/10.1038/sdata.2016.34)
- Schvitz, G., Girardin, L., Rüegger, S., Weidmann, N. B., Cederman, L.-E. and Gleditsch, K. S. (2022). Mapping the international system, 1886-2019: the CShapes 2.0 dataset. *Journal of Conflict Resolution* 66(1), 144-161. [doi:10.1177/00220027211013563](https://doi.org/10.1177/00220027211013563)

## License

MIT
