module HistoricalGeographyHydeExt

using HistoricalGeography, ArchGDAL, DBInterface
using HistoricalGeography: HYDE, hyde_file, rows, quoted

"""The years of HYDE's grids, from the days since 1 January of the year 1 (a calendar of 365 days) in the file's metadata."""
function hyde_years(dataset)
	entry = only(filter(m -> startswith(m, "NETCDF_DIM_time_VALUES="), ArchGDAL.metadata(dataset)))
	return parse.(Int, split(strip(split(entry, "=")[2], ['{', '}']), ",")) .÷ 365 .+ 1
end

function population_grid(con; folder::AbstractString, box = (-12, 34, 45, 72), since::Union{Integer, Nothing} = nothing,
		upto::Union{Integer, Nothing} = nothing, cell::Real = 0.5, table::AbstractString = "grid")
	length(box) == 4 || throw(ArgumentError("box is (west, south, east, north), in degrees"))
	path = hyde_file(; folder)
	west, south, east, north = Float64.(box)
	csv = tempname() * ".csv"
	years, size = ArchGDAL.read(path) do dataset
		origin_x, step, _, origin_y, _, step_y = ArchGDAL.getgeotransform(dataset)
		k = max(1, round(Int, cell / step))  # grid cells to a side of a cell
		size = k * step
		# the cells of the box, whole cells of the grid, within the file
		x0 = max(0, floor(Int, (west - origin_x) / step))
		y0 = max(0, floor(Int, (origin_y - north) / -step_y))
		nx = min(ArchGDAL.width(dataset) - x0, ceil(Int, (east - west) / step)) ÷ k * k
		ny = min(ArchGDAL.height(dataset) - y0, ceil(Int, (north - south) / -step_y)) ÷ k * k
		(nx > 0 && ny > 0) || error("the box is smaller than a cell of $(cell) degrees")
		all = hyde_years(dataset)
		bands = findall(y -> (since === nothing || y >= since) && (upto === nothing || y <= upto), all)
		isempty(bands) && error("$(HYDE) has grids from $(first(all)) to $(last(all)), none in the years asked")
		radius = 6371.0088  # km, the mean radius of the Earth
		open(csv, "w") do io
			println(io, "lon,lat,year,population,km2")
			for b in bands
				grid = ArchGDAL.read(ArchGDAL.getband(dataset, b), x0, y0, nx, ny)
				for cy in 1:ny ÷ k, cx in 1:nx ÷ k
					people = 0.0
					for v in @view grid[(cx - 1) * k + 1:cx * k, (cy - 1) * k + 1:cy * k]
						v > 0 && (people += v)
					end
					people > 0 || continue
					top = origin_y + (y0 + (cy - 1) * k) * step_y
					lon = origin_x + (x0 + (cx - 0.5) * k) * step
					km2 = radius^2 * deg2rad(size) * abs(sind(top) - sind(top - size))
					println(io, round(lon; digits = 6), ",", round(top - size / 2; digits = 6), ",", all[b], ",", people, ",", km2)
				end
			end
		end
		return all[bands], size
	end
	DBInterface.execute(con, """CREATE OR REPLACE TABLE "$(table)" AS SELECT * FROM read_csv('$(quoted(csv))', header = true,
		columns = {lon: 'DOUBLE', lat: 'DOUBLE', year: 'INTEGER', population: 'DOUBLE', km2: 'DOUBLE'})""")
	rm(csv)
	span = rows(con, """SELECT min(year) AS low, max(year) AS high FROM "$(table)" """)
	span.low[1] === missing && error("$(HYDE) has no people in this box in the years asked")
	return (; source = HYDE, since = Int(span.low[1]), upto = Int(span.high[1]), years, cell = round(size; digits = 4))
end

end
