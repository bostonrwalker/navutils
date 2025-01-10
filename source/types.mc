import Toybox.Lang;


module NavUtils {
    
    // N/S hemisphere designator for UTM
    enum Hemisphere {
        SOUTH,
        NORTH,
    }

    /*
    Lat/long (geodetic) type:
    
    [0]: Latitude in decimal degrees (+ve for N, -ve for S)
    [1]: Longitude in decimal degrees (+ve for E, -ve for W)
    */
    typedef LatLong as [Float, Float];

    /*
    UTM type:

    [0]: Hemisphere (N or S)
    [1]: UTM zone (e.g. "18T")
    [2]: UTM easting in meters
    [3]: UTM northing in meters
    */
    typedef UTM as [Hemisphere, String, Number, Number];

    /*
    MGRS type:

    [0]: UTM zone (e.g. "18T")
    [1]: MGRS grid reference (e.g. "UV")
    [2]: MGRS easting (1 meter precision)
    [3]: MGRS northing (1 meter precision)
    */
    typedef MGRS as [String, String, Number, Number];
}
