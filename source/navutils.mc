import Toybox.Lang;
using Toybox.Time;
using Toybox.Position;
using Toybox.Math;
using Toybox.Test;


/*******************************************************************************
Main NavUtils module
********************************************************************************
Functions for working with headings in Degrees, DMS, Radians, and Mils

Created: 11 Jan 2025 by Boston W
*******************************************************************************/


module NavUtils {
    /*******************************************************************************
    Typedefs
    *******************************************************************************/
    /*
    Radians type alias. Added for clarity when defining method signatures.

    Range: [-2 * pi, 2 * pi)
    */
    typedef Radians as Float;

    /*
    Decimal degrees type alias. Added for clarity when defining method signatures.

    Range: [-180, 180)
    */
    typedef DecimalDegrees as Numeric;

    /*
    Lat/long (geodetic) type:
    
    [0]: Latitude in decimal degrees (+ve for N, -ve for S)
    [1]: Longitude in decimal degrees (+ve for E, -ve for W)
    */
    typedef LatLong as [DecimalDegrees, DecimalDegrees];

    /*
    Degrees, minutes, seconds:

    [0]: Integer degrees East (+ve) or West (-ve), range: [-180, 180)
    [1]: Integer minutes, range: [0, 60)
    [2]: Integer or decimal seconds, range: [0, 60)
    */
    typedef DMS as [Number, Number, Numeric];

    /*
    Integer mils. Added for clarity when defining method signatures. Range: [0, 6400)
    */
    typedef Mils as Number;

    /*
    Meters. Added for clarity when defining method signatures/units. Range: [0, Inf)
    */
    typedef Meters as Numeric;


    /*******************************************************************************
    Parsing and formatting functions
    *******************************************************************************/

    function readLatLong(str as String, options as {:delimiter as String}) as LatLong {
        /*
        Parse comma-separated decimal lat/long string
    
        :param str: Lat/long cooordinates to read
        :param options:
            :delimiter: Delimiter to look for between lat and long values (default: ",")
        :raise: InvalidValueException if string is invalid
        */
        var delimiter = Utils.getDefault(options, :delimeter, ",") as String;
        var parts = StringUtils.split(str, delimiter);
        if (parts.size() != 2) {
            throw new ValueError(
                "Invalid position: \"" + str + "\"");
        }

        var latitude = parts[0].toFloat();
        var longitude = parts[1].toFloat();
        if (latitude == null || longitude == null || 
                latitude < -90 || latitude > 90 || longitude <= -180 || longitude > 180) {
            throw new ValueError(
                "Invalid position: \"" + str + "\"");
        }

        return [latitude, longitude];
    }

    function dumpLatLong(latLong as LatLong, options as {:delimiter as String}) as String {
        /*
        Format position as comma-separated decimal lat/long string with 8 decimal places

        :param latLong: Lat/long cooordinates to format
        :param options:
            :delimiter: Delimiter to put between lat and long values (default: ",")
        */
        var delimiter = Utils.getDefault(options, :delimeter, ",") as String;
        return latLong[0].format("%.8f") + delimiter + latLong[1].format("%.8f");
    }

    /*******************************************************************************
    Addition and conversion
    *******************************************************************************/

    function addRadians(angle as Radians?, delta as Radians?) as Radians? {
        /*
        Add radians to a base angle, while keeping in [0, 2 pi) range

        :param angle: Angle in radians. Must be in range [0, 2 * pi)
        :param delta: Differential angle in radians. Must be in range [-2 * pi, 2 * pi)
        :return: (a + b) mod 2 * pi, in range [0, 2 * pi)
        */
        if (angle == null || delta == null) {
            return null;
        }
        var result = angle + delta;
        if (result < 0) {
            result += TWO_PI;
        } else if (result >= TWO_PI) {
            result -= TWO_PI;
        }
        return result;
    }

    function radsToMils(radians as Radians?) as Mils? {
        /*
        Convert radians to mils

        :param radians: Angle in radians. Must be in range [-2 * pi, 2 * pi)
        :return: Integer mils in range [0, 6400)
        */
        if (radians == null) {
            return null;
        } else {
            if (radians < 0.0) {
                // Put into [0, 2 * pi) range
                radians += TWO_PI;
            }
            return Math.round(radians * 6400.0 / TWO_PI).toNumber();
        }
    }

    function milsToRads(mils as Mils?) as Radians? {
        // Convert radians to mils
        if (mils == null) {
            return null;
        } else {
            return mils * TWO_PI / 6400.0;
        }
    }

    function degreesToRads(degrees as DecimalDegrees?) as Radians? {
        // Convert degrees to radians
        if (degrees == null) {
            return null;
        } else {
            return degrees * TWO_PI / 360.0;
        }
    }

    function radsToDegrees(rads as Radians?) as DecimalDegrees? {
        // Convert radians to degrees
        if (rads == null) {
            return null;
        } else {
            return rads * 360.0 / TWO_PI;
        }
    }

    function radsToCardinalDir(rads as Radians, precision as Number) as String {
        // Convert radians to cardinal direction
        // Precision 1: N, E, S, W
        // Precision 2: NE, SW, etc.
        // Precision 3: NNE, SSW, ESW, etc.
        if (precision == 1) {
            var index = Math.round(4.0f * (rads / TWO_PI)).toNumber() % 4;
            return CARDINAL_DIRS_PRECISION_1[index];
        } else if (precision == 2) {
            var index = Math.round(8.0f * (rads / TWO_PI)).toNumber() % 8;
            return CARDINAL_DIRS_PRECISION_2[index];
        } else if (precision == 3) {
            var index = Math.round(16.0f * (rads / TWO_PI)).toNumber() % 16;
            return CARDINAL_DIRS_PRECISION_3[index];
        } else {
            throw new ValueError(
                "Invalid precision: " + precision.toString());
        }
    }

    function decimalDegreesToDMS(degrees as DecimalDegrees) as DMS {
        /*
        Convert decimal degrees to integer degrees, minutes, seconds

        Return values are rounded to the nearest second.

        :param degrees: Decimal degrees. Must be non-negative, i.e. in range [0, infinity).
        :return: Tuple [degrees, minutes, seconds]
        */
        if (degrees < 0) {
            throw new ValueError(
                "`degrees` must be non-negative");
        } else {
            var seconds = Math.round(degrees * 3600).toNumber();
            return [
                seconds / 3600,  // Degrees
                (seconds % 3600) / 60,  // Minutes
                seconds % 60,  // Seconds
            ];
        }
    }

    function dmsToDecimalDegrees(dms as DMS) as DecimalDegrees {
        /*
        Convert integer degrees, minutes, seconds to decimal degrees

        :param degrees: Degrees. Must be non-negative, i.e. in range [0, infinity).
        :param minutes: Minutes. Must be non-negative, i.e. in range [0, infinity).
        :param seconds: Seconds. Must be non-negative, i.e. in range [0, infinity).
        :return: Value in decimal degrees.
        */
        var degrees = dms[0];
        var minutes = dms[1];
        var seconds = dms[2];

        return degrees.toFloat() + minutes / 60.0 + seconds / 3600.0;
    }

    function locationToLatLong(location as Position.Location) as LatLong {
        /*
        Convert Position.Location to LatLong (geodetic)
        */
        var doubleDegrees = location.toDegrees();
        return [doubleDegrees[0].toFloat(), doubleDegrees[1].toFloat()];
    }

    function latLongToLocation(latLong as LatLong) as Position.Location {
        /*
        Convert LatLong (geodetic) to Position.Location
        */
        return new Position.Location({:latitude => latLong[0], :longitude => latLong[1], :format => :degrees});
    }

    /*******************************************************************************
    Distance and bearing using Great circle
    ********************************************************************************
    Prior art: https://www.movable-type.co.uk/scripts/latlong.html
    *******************************************************************************/

    function distance(p1 as LatLong or Position.Location, p2 as LatLong or Position.Location) as Meters {
        /*
        Compute the Great Circle distance between two points on Earth's surface using the Haversine formula.
        http://www.movable-type.co.uk/scripts/latlong.html

        :param p1: Point in geodetic (lat/long) coordinates
        :param p2: Point in geodetic (lat/long) coordinates
        :return: Great circle distance in meters
        */
        // Handle Position.Location objects
        p1 = p1 instanceof Position.Location ? locationToLatLong(p1) : p1;
        p2 = p2 instanceof Position.Location ? locationToLatLong(p2) : p2;

        // Convert degrees to rads
        var lat1 = p1[0] * TWO_PI / 360.0f;
        var long1 = p1[1] * TWO_PI / 360.0f;
        var lat2 = p2[0] * TWO_PI / 360.0f;
        var long2 = p2[1] * TWO_PI / 360.0f;

        // Take the difference
        var deltaLat = lat2 - lat1;
        var deltaLong = long2 - long1;

        // Reused quantities
        var sinDeltaLatOver2 = Math.sin(deltaLat / 2.0f);
        var sinDeltaLongOver2 = Math.sin(deltaLong / 2.0f);

        var a = sinDeltaLatOver2 * sinDeltaLatOver2 + Math.cos(lat1) * Math.cos(lat2) * sinDeltaLongOver2 * sinDeltaLongOver2;
        var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

        return R * c;
    }
    
    function bearing(start as LatLong or Position.Location, end as LatLong or Position.Location) as Radians {
        /*
        Compute initial bearing along Great Circle from start point to end point
        http://www.movable-type.co.uk/scripts/latlong.html

        :param start: Point in geodetic (lat/long) coordinates
        :param end: Point in geodetic (lat/long) coordinates
        :return: Bearing from start to end along Great Circle in radians
        */
        // Handle Position.Location objects
        start = start instanceof Position.Location ? locationToLatLong(start) : start;
        end = end instanceof Position.Location ? locationToLatLong(end) : end;

        // Convert degrees to rads
        var lat1 = start[0] * TWO_PI / 360.0f;
        var long1 = start[1] * TWO_PI / 360.0f;
        var lat2 = end[0] * TWO_PI / 360.0f;
        var long2 = end[1] * TWO_PI / 360.0f;

        // Take the difference
        var deltaLong = long2 - long1;

        // Do some trig
        var y = Math.sin(deltaLong) * Math.cos(lat2);
        var x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(deltaLong);
        var theta = Math.atan2(y, x);
        if (theta < 0.0f) {
            theta += TWO_PI;
        }
        return theta;
    }
    
    function distanceAndBearing(start as LatLong or Position.Location, end as LatLong or Position.Location) as [Meters, Radians] {
        /*
        Compute distance and initial bearing along Great Circle from start point to end point.
        More efficient than using distance() and bearing() functions separately.
        http://www.movable-type.co.uk/scripts/latlong.html

        :param start: Point in geodetic (lat/long) coordinates
        :param end: Point in geodetic (lat/long) coordinates
        :return: Distance in meters and bearing in radians from start to end along Great Circle
        */
        // Handle Position.Location objects
        start = start instanceof Position.Location ? locationToLatLong(start) : start;
        end = end instanceof Position.Location ? locationToLatLong(end) : end;

        // Convert degrees to rads
        var lat1 = start[0] * TWO_PI / 360.0f;
        var long1 = start[1] * TWO_PI / 360.0f;
        var lat2 = end[0] * TWO_PI / 360.0f;
        var long2 = end[1] * TWO_PI / 360.0f;

        // Take the difference
        var deltaLat = lat2 - lat1;
        var deltaLong = long2 - long1;
    
        // Reused quantities
        var sinDeltaLatOver2 = Math.sin(deltaLat / 2.0f);
        var sinDeltaLongOver2 = Math.sin(deltaLong / 2.0f);
        var cosLat1 = Math.cos(lat1);
        var cosLat2 = Math.cos(lat2);

        // Do some trig
        var a = sinDeltaLatOver2 * sinDeltaLatOver2 + Math.cos(lat1) * Math.cos(lat2) * sinDeltaLongOver2 * sinDeltaLongOver2;
        var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

        var y = Math.sin(deltaLong) * cosLat2;
        var x = cosLat1 * Math.sin(lat2) - Math.sin(lat1) * cosLat2 * Math.cos(deltaLong);
        var theta = Math.atan2(y, x);
        if (theta < 0.0f) {
            theta += TWO_PI;
        }

        return [R * c, theta];
    }

    /*******************************************************************************
    Compass headings
    *******************************************************************************/

    function getBearingFromMagneticNorth(a as [Numeric, Numeric, Numeric]?, m as [Numeric, Numeric, Numeric]?, options as {
            :minAccelerometer as Numeric, :minMagnetometer as Numeric, :minAngle as Numeric}) as Radians? {
        /*
        Compute bearing of device vs. magnetic north

        Bearing is defined as the angle between a device reference direction and the measured direction to
        magnetic north, when both are projected into the lateral plane defined by the direction of gravity.

        Uses positive x direction (device right hand direction) as reference. E.g. when facing N, positive
        x direction will be facing E, and bearing will be 0. This means the user can view the device at any
        pitch, since pitch is rotation around X axis. Yaw and roll can affect bearing however.

        :param a: Accelerometer reading [x, y, z] in milli-Gs
        :param m: Magnetometer reading [x, y, z] in milli-Gauss
        :param options:
            :minAccelerometer: Minimum magnitude of accelerometer reading in milli-Gs (default: 750)
            :minMagnetometer: Minimum magnitude of magnetometer reading in milli-Gauss (default: 100)
            :minAngle: Minimum angle in degrees between accelerometer and magnetometer (default: 8)
        :return: Bearing in radians (if defined) in range [0, 2 * pi)
        */       
        var minAccelerometer = Utils.getDefault(options, :minAccelerometer, 750.0f) as Float;
        var minMagnetometer = Utils.getDefault(options, :minMagnetometer, 100.0f) as Float;
        var minAngleDegrees = Utils.getDefault(options, :minAngle, 8.0f) as Numeric;

        if ((a == null) || (m == null)) {
            // Null sensor data sometimes supplied on app startup
            return null;
        }

        // Unpack arrays
        var ax = a[0];
        var ay = a[1];
        var az = a[2];

        var mx = m[0];
        var my = m[1];
        var mz = m[2];

        // Normalize accel and mag vectors
        var magA = Math.sqrt(ax * ax + ay * ay + az * az);
        var magM = Math.sqrt(mx * mx + my * my + mz * mz);

        if (magA <= minAccelerometer || magM <= minMagnetometer) {
            // Vectors must be non-zero
            return null;
        }

        ax /= magA;
        ay /= magA;
        az /= magA;

        mx /= magM;
        my /= magM;
        mz /= magM;

        // Dot product of unit vectors (cosine of angle)
        var aDotM = (ax * mx + ay * my + az * mz);

        var maxCosine = Math.acos(minAngleDegrees * TWO_PI / 360.0);
        if (aDotM >= maxCosine || aDotM <= -maxCosine) {
            // Angle between magnetometer and accelerometer is too small
            return null;
        }

        // Lateral component of unit magnetic vector
        var mLatX = mx - aDotM * ax;
        var mLatY = my - aDotM * ay;
        var mLatZ = mz - aDotM * az;

        var magMLat = Math.sqrt(mLatX * mLatX + mLatY * mLatY + mLatZ * mLatZ);
        if (magMLat == 0) {
            // This shouldn't happen
            return null;
        }

        mLatX /= magMLat;
        mLatY /= magMLat;
        mLatZ /= magMLat;

        // Lateral component of unit reference vector ([1, 0, 0])
        var rLatX = 1.0 - ax * ax;
        var rLatY = -ax * ay;
        var rLatZ = -ax * az;

        var magRLat = Math.sqrt(rLatX * rLatX + rLatY * rLatY + rLatZ * rLatZ);
        if (magRLat == 0) {
            // This shouldn't happen
            return null;
        }

        rLatX /= magRLat;
        rLatY /= magRLat;
        rLatZ /= magRLat;

        // m_lat cross r_lat
        var cosTheta = mLatX * rLatX + mLatY * rLatY + mLatZ * rLatZ;

        // a dot (m_lat cross r_lat)
        // Equivalent to taking signed magnitude of cross product of m_lat and r_lat
        var sinTheta = ax * (mLatY * rLatZ - mLatZ * rLatY) + ay * (mLatZ * rLatX - mLatX * rLatZ) + az * (mLatX * rLatY - mLatY * rLatX);

        // Equivalent to atan2(sin(theta - (pi / 2)), cos(theta - (pi / 2)))
        // Need to apply a 90 degree phase shift since the reference vector points E when facing N.
        var angle = Math.atan2(-cosTheta, sinTheta);
        if (angle < 0) {
            // Ensure angle is in range [0, 2 * pi)
            angle += TWO_PI;
        }
        return angle;
    }

    function applyMagneticDeclination(heading as Radians?, magDec as DecimalDegrees?) as Radians? {
        /*
        Subtract magnetic declination from magnetic N heading

        :param heading: Heading from magnetic N in rads
        :param magDec: Mag dec in degrees. Per convention W is positive and E is negative.
        */
        return addRadians(heading, degreesToRads(magDec));
    }


    (:test)
    function testAddRadians(logger as Test.Logger) as Boolean {
        TestUtils.assertFloatEqual(addRadians(0.0, Math.PI / 2), Math.PI / 2, {:tol => 1e-6});
        TestUtils.assertFloatEqual(addRadians(0.0, -Math.PI / 2), 3 * Math.PI / 2, {:tol => 1e-6});
        TestUtils.assertFloatEqual(addRadians(0.0, 2 * Math.PI), 0.0, {:tol => 1e-6});
        TestUtils.assertFloatEqual(addRadians(0.0, -2 * Math.PI), 0.0, {:tol => 1e-6});
        TestUtils.assertFloatEqual(addRadians(Math.PI, Math.PI), 0.0, {:tol => 1e-6});
        TestUtils.assertFloatEqual(addRadians(Math.PI / 2, -Math.PI / 2), 0.0, {:tol => 1e-6});
        return true;
    }


    (:test)
    function testGetBearingFromMagneticNorth(logger as Test.Logger) as Boolean {

        // Test scenario 1: Magnetic field of 400 uT parallel to ground

        // --- FACING N --- //
        // Looking down at device
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, -1000.0], [0.0, 400.0, 0.0], {}), 0.0, {:tol => 1e-6});

        // Bring the device to eye level
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([0.0, -1000.0, 0.0], [0.0, 0.0, -400.0], {}), 0.0, {:tol => 1e-6});

        // Tilt it 45* left or right
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([-707.0, -707.0, 0.0], [0.0, 0.0, -400.0], {}), 0.0, {:tol => 1e-6});
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([707.0, -707.0, 0.0], [0.0, 0.0, -400.0], {}), 0.0, {:tol => 1e-6});

        // Looking straight up at device
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, 1000.0], [0.0, -400.0, 0.0], {}), 0.0, {:tol => 1e-6});

        // --- FACING NE --- //
        // Looking down at device
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, -1000.0], [-283.0, 283.0, 0.0], {}), Math.PI / 4, {:tol => 1e-6});

        // --- FACING E --- //
        // Looking down at device
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, -1000.0], [-400.0, 0.0, 0.0], {}), Math.PI / 2, {:tol => 1e-6});

        // Bring the device to eye level
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([0.0, -1000.0, 0.0], [-400.0, 0.0, 0.0], {}), Math.PI / 2, {:tol => 1e-6});

        // Tilt it 45* left or right
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([-707.0, -707.0, 0.0], [-283.0, 283.0, 0.0], {}), Math.PI / 2, {:tol => 1e-6});
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([707.0, -707.0, 0.0], [-283.0, -283.0, 0.0], {}), Math.PI / 2, {:tol => 1e-6});

        // Looking straight up at device
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, 1000.0], [-400.0, 0.0, 0.0], {}), Math.PI / 2, {:tol => 1e-6});

        // --- FACING SE --- //
        // Looking down at device
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, -1000.0], [-283.0, -283.0, 0.0], {}), 3 * Math.PI / 4, {:tol => 1e-6});

        // --- FACING S --- //
        // Looking down at device
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, -1000.0], [0.0, -400.0, 0.0], {}), Math.PI, {:tol => 1e-6});

        // Bring the device to eye level
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([0.0, -1000.0, 0.0], [0.0, 0.0, 400.0], {}), Math.PI, {:tol => 1e-6});

        // Tilt it 45* left or right
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([-707.0, -707.0, 0.0], [0.0, 0.0, 400.0], {}), Math.PI, {:tol => 1e-6});
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([707.0, -707.0, 0.0], [0.0, 0.0, 400.0], {}), Math.PI, {:tol => 1e-6});

        // Looking straight up at device
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, 1000.0], [0.0, 400.0, 0.0], {}), Math.PI, {:tol => 1e-6});

        // --- FACING SW --- //
        // Looking down at device
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, -1000.0], [283.0, -283.0, 0.0], {}), 5 * Math.PI / 4, {:tol => 1e-6});

        // --- FACING W --- //
        // Looking down at device
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, -1000.0], [400.0, 0.0, 0.0], {}), 3 * Math.PI / 2, {:tol => 1e-6});

        // Bring the device to eye level
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([0.0, -1000.0, 0.0], [400.0, 0.0, 0.0], {}), 3 * Math.PI / 2, {:tol => 1e-6});

        // Tilt it 45* left or right
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([-707.0, -707.0, 0.0], [283.0, -283.0, 0.0], {}), 3 * Math.PI / 2, {:tol => 1e-6});
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([707.0, -707.0, 0.0], [283.0, 283.0, 0.0], {}), 3 * Math.PI / 2, {:tol => 1e-6});

        // Looking straight up at device
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, 1000.0], [400.0, 0.0, 0.0], {}), 3 * Math.PI / 2, {:tol => 1e-6});

        // --- FACING NW --- //
        // Looking down at device
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, -1000.0], [283.0, 283.0, 0.0], {}), 7 * Math.PI / 4, {:tol => 1e-6});


        // Test scenario 2: Magnetic field of 500 uT running down into ground at 53.13 degrees (3-4-5 triangle)

        // Facing N, looking down at device
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, -1000.0], [0.0, 300.0, -400.0], {}), 0.0, {:tol => 1e-6});

        // Facing W, looking across at device
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([0.0, -1000.0, 0.0], [-300.0, -400.0, 0.0], {}), Math.PI / 2, {:tol => 1e-6});

        // Facing S, looking straight up at device
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, 1000.0], [0.0, 300.0, 400.0], {}), Math.PI, {:tol => 1e-6});


        // Test scenario 3: Magnetic field aligned with gravity
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, -1000.0], [0.0, 0.0, -500.0], {}), null, {});

        // Test scenario 4: Weak magnetic field
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, -1000.0], [0.0, 50.0, 0.0], {}), null, {});

        // Test scenario 5: Weak gravity
        TestUtils.assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, -500.0], [0.0, 300.0, 0.0], {}), null, {});

        return true;
    }
}