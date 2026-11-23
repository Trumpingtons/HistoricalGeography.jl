module HistoricalGeographyTilesExt

using HistoricalGeography, ArchGDAL

"""The half width of the world in Web Mercator, in metres."""
const HALF = 20037508.342789244

"""The XML of GDAL's WMS driver that reads the tiles of `url` at one zoom, as a raster of the whole world."""
function tile_service(url::AbstractString, zoom::Int, tilesize::Int)
	server = replace(url, "{z}" => "\${z}", "{x}" => "\${x}", "{y}" => "\${y}", "&" => "&amp;")
	return """<GDAL_WMS>
<Service name="TMS"><ServerUrl>$(server)</ServerUrl></Service>
<DataWindow><UpperLeftX>$(-HALF)</UpperLeftX><UpperLeftY>$(HALF)</UpperLeftY><LowerRightX>$(HALF)</LowerRightX><LowerRightY>$(-HALF)</LowerRightY>
<TileLevel>$(zoom)</TileLevel><TileCountX>1</TileCountX><TileCountY>1</TileCountY><YOrigin>top</YOrigin></DataWindow>
<Projection>EPSG:3857</Projection><BlockSizeX>$(tilesize)</BlockSizeX><BlockSizeY>$(tilesize)</BlockSizeY><BandsCount>4</BandsCount>
<UserAgent>$(last(HistoricalGeography.AGENT))</UserAgent><MaxConnections>2</MaxConnections><Timeout>180</Timeout>
<ZeroBlockHttpCodes>204,404</ZeroBlockHttpCodes><ZeroBlockOnServerException>true</ZeroBlockOnServerException>
</GDAL_WMS>"""
end

function tiles_geotiff(url::AbstractString, box::NTuple{4, Float64}, zoom::Int, path::AbstractString, tilesize::Int)
	west, south, east, north = box
	(west < east && south < north) || throw(ArgumentError("box is (west, south, east, north), with west < east and south < north"))
	# a tile server that draws its tiles on request can be slow or drop a connection: two at a time, each tried four times
	ArchGDAL.environment(; threadconfig = ["GDAL_HTTP_MAX_RETRY" => "4", "GDAL_HTTP_RETRY_DELAY" => "5"]) do
		ArchGDAL.read(tile_service(url, zoom, tilesize)) do service
			ArchGDAL.gdaltranslate(service, ["-of", "GTiff", "-projwin_srs", "EPSG:4326", "-projwin", string(west), string(north),
				string(east), string(south), "-co", "COMPRESS=DEFLATE", "-co", "TILED=YES"]; dest = path) do _
			end
		end
	end
	return path
end

end
