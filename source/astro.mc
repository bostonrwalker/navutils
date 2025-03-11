import Toybox.Lang;
using Toybox.Time;
using Toybox.Position;
using Toybox.Math;
using Toybox.Graphics;
using Toybox.Test;
using Toybox.System;


/*******************************************************************************
Astronomical NavUtils module
********************************************************************************
Functions for working with astronomical coordinate systems

Created: 19 Feb 2025 by Boston W
*******************************************************************************/

// J2000.0 - astronomical base time
const J2000_0 = Time.Gregorian.moment({
    :year => 2000,
    :month => 1,
    :day => 1,
    :hour => 12,
    :minute => 0,
    :second => 0,
});

module NavUtils {
    /*******************************************************************************
    Typedefs
    *******************************************************************************/
    /*
    Celestial equatorial coordinate system

    [0]: Right ascension in radians E of 0h, range: [0, 2 * pi)
    [1]: Declination in radians N or S of the celestial equator, range: [-pi, pi]
    */
    typedef Equatorial as [Radians, Radians];

    /*
    Horizontal coordinate system

    [0]: Azimuth in radians clockwise of N, range: [0, 2 * pi)
    [1]: Altitude in radians above or below horizon, range: [-pi, pi]
    */
    typedef Horizontal as [Radians, Radians];

    /*
    3-axis attitude in radians.
    */
    typedef Attitude as [Radians, Radians, Radians];


    function getHorizontalAttitude(a as [Numeric, Numeric, Numeric]?, m as [Numeric, Numeric, Numeric]?, options as {
        :magDec as DecimalDegrees, :minAccelerometer as Numeric, :minMagnetometer as Numeric, :minAngle as Numeric}) as Attitude? {
        /*
        Compute azimuth and altitude of device -z vector, as well as device roll around this axis

        This azimuth differs from `getBearingFromMagneticNorth` because it is based on the -z vector and not +x vector, and also takes mag dec into account

        Used to determine where in the sky the user is pointing their watch

        :param a: Accelerometer reading [x, y, z] in milli-Gs
        :param m: Magnetometer reading [x, y, z] in milli-Gauss
        :param options:
            :magDec: Magnetic declination in degrees E of N (default: 0)
            :minAccelerometer: Minimum magnitude of accelerometer reading in milli-Gs (default: 750)
            :minMagnetometer: Minimum magnitude of magnetometer reading in milli-Gauss (default: 100)
            :minAngle: Minimum angle in degrees between accelerometer and magnetometer (default: 8)
        :return: 
            [0]: Azimuth (if defined) in radians E of true N, range [0, 2 * pi)
            [1]: Altitude (if defined) in radians above or below horizon, range: [-pi, pi]
            [2]: Roll (if defined) in radians CW of vertical, range; [0, 2 * pi)
        */       
        var magDec = Utils.getDefault(options, :magDec, 0.0f) as DecimalDegrees;
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

        // Unit reference vector R: [0, 0, -1]
        // Compute lateral component R_lat
        var rLatX = az * ax;
        var rLatY = az * ay;
        var rLatZ = -1.0 + az * az;

        var magRLat = Math.sqrt(rLatX * rLatX + rLatY * rLatY + rLatZ * rLatZ);
        if (magRLat == 0) {
            // This shouldn't happen
            return null;
        }

        rLatX /= magRLat;
        rLatY /= magRLat;
        rLatZ /= magRLat;

        // m_lat cross r_lat
        var cosAzimuth = mLatX * rLatX + mLatY * rLatY + mLatZ * rLatZ;

        // a dot (m_lat cross r_lat)
        // Equivalent to taking signed magnitude of cross product of m_lat and r_lat
        var sinAzimuth = ax * (mLatY * rLatZ - mLatZ * rLatY) + ay * (mLatZ * rLatX - mLatX * rLatZ) + az * (mLatX * rLatY - mLatY * rLatX);

        var azimuth = Math.atan2(sinAzimuth, cosAzimuth);
        if (azimuth < 0) {
            // Ensure angle is in range [0, 2 * pi)
            azimuth += TWO_PI;
        }
        if (magDec != 0) {
            azimuth = applyMagneticDeclination(azimuth, magDec);
        }

        // Easy to compute altitude and roll from acceleration vector alone
        var altitude = Math.asin(az);
        var roll = Math.atan2(ax, -ay);
        
        return [azimuth, altitude, roll];
    }

    function getSiderealTime(currentTime as Time.Moment, longitude as Radians) as Radians {
        /*
        Get local sidereal time using current time and location

        Based on https://aa.usno.navy.mil/faq/GAST

        Most simplified version of calculations, does not account for leap seconds or quadratic terms
        Ignore equation of the equinoxes
        */
        var secondsSinceBase = currentTime.subtract(J2000_0).value();  // 64-bit Number
        var daysSinceBase = secondsSinceBase / 86400;  // Integer days UTC since 2000-01-01
        var hourFraction = (secondsSinceBase % 86400) / 86400.0;  // Fraction of day UTC in radians
        // Note: decomposing into integer days vs. hours before modulo increases precision
        var gmst = (0.77905727325 + 0.0027379093449583 * daysSinceBase + 1.0027379093449583 * hourFraction);  // As days
        gmst -= Math.floor(gmst);  // As fraction of a day
        gmst *= TWO_PI;  // In radians
        var lst = gmst + longitude;
        if (lst < 0) {
            lst += TWO_PI;
        } else if (lst > TWO_PI) {
            lst -= TWO_PI;
        }
        return lst as Radians;
    }

    function equatorialToHorizontalCoords(equatorial as Equatorial, currentTime as Time.Moment, location as LatLong or Position.Location) as Horizontal {
        /*
        Convert equatorial to horizontal coords, using current time and location on Earth

        See: http://www-star.st-andrews.ac.uk/~fv/webnotes/chapter7.htm

        :param equatorial: Equatorial celestial coordinates in radians
            [0]: Right ascension, range: [0, 2 * pi)
            [1]: Declination, range: [-pi, pi]
        :param currentTime: Current GMT
        :param location: Location as LatLong (degrees) or Toybox.Position.Location object
        */
        var longitude;
        var latitude;
        if (location instanceof Position.Location) {
            var latLongRadians = location.toRadians();
            latitude = latLongRadians[0] as Radians;
            longitude = latLongRadians[1] as Radians;
        } else {
            latitude = (location[0] * TWO_PI / 360.0) as Radians;
            longitude = (location[1] * TWO_PI / 360.0) as Radians;
        }

        var cosLat = Math.cos(latitude);
        if (cosLat == 0) {
            throw new ValueError(
                "Zenith cannot be defined at N or S poles!");
        }
        var sinLat = Math.sin(latitude);

        // Local sidereal time, radians
        var lst = getSiderealTime(currentTime, longitude);

        // Unpack coordinates
        var rightAscension = equatorial[0];
        var declination = equatorial[1];

        // Local hour angle of equatorial body in radians
        // Note: lha here has range (-2 * pi, 2 * pi). This is fine for the purposes of taking sin and cos.
        var lha = (lst - rightAscension) as Radians; 
        if (lha < 0) {
            lha += TWO_PI;
        }
        var cosLha = Math.cos(lha);

        var cosDeclination = Math.cos(declination);
        var sinDeclination = Math.sin(declination);

        // Calculate altitude: angle above or below the horizon, range: [-pi / 2, pi / 2]
        var sinAltitude = sinDeclination * sinLat + cosDeclination * cosLat * cosLha;
        var altitude = Math.asin(sinAltitude);  // Works fine for range [-pi / 2, pi / 2]
    
        var azimuth;
        if ((altitude.abs() - HALF_PI).abs() > 1e-6) {
            // Star is not exactly at zenith or antizenith
            var cosAltitude = Math.sqrt(1 - sinAltitude * sinAltitude);  // Use trig identity. Works fine for range [-pi / 2, pi / 2]
            var cosAzimuth = (sinDeclination - sinLat * sinAltitude) / (cosLat * cosAltitude);
            if (cosAzimuth >= 1) {
                // Deal with numerical imprecision
                azimuth = 0.0;
            } else if (cosAzimuth <= -1) {
                // Deal with numerical imprecision
                azimuth = Math.PI;
            } else if (lha >= Math.PI) {
                azimuth = Math.acos(cosAzimuth);
            } else {
                azimuth = TWO_PI - Math.acos(cosAzimuth);
            }
        } else {
            // Altitude is either +90 degrees or -90 degrees
            // In this case, azimuth is not well-defined. Zero value is arbitrary.
            azimuth = 0.0;  
        }

        return [azimuth, altitude] as Horizontal;
    }

    function horizontalToEquatorialAttitude(horizontal as Attitude, currentTime as Time.Moment, location as LatLong or Position.Location) as Attitude {
        /*
        Convert horizontal attitude to equatorial attitude, using current time and location on Earth
        
        See: http://www-star.st-andrews.ac.uk/~fv/webnotes/chapter7.htm

        :param horizontal: Horizontal celestial coordinates in radians
            [0]: Azimuth, range: [0, 2 * pi)
            [1]: Altitude, range: [-pi, pi]
        :param currentTime: Current GMT
        :param location: Location as LatLong (degrees) or Toybox.Position.Location object
        */
        var longitude;
        var latitude;
        if (location instanceof Position.Location) {
            var latLongRadians = location.toRadians();
            latitude = latLongRadians[0] as Radians;
            longitude = latLongRadians[1] as Radians;
        } else {
            latitude = (location[0] * TWO_PI / 360.0) as Radians;
            longitude = (location[1] * TWO_PI / 360.0) as Radians;
        }

        var cosLat = Math.cos(latitude);
        var sinLat = Math.sin(latitude);

        // Local sidereal time, radians
        var lst = getSiderealTime(currentTime, longitude);

        // Unpack coordinates
        var azimuth = horizontal[0]; 
        var altitude = horizontal[1];
        var roll = horizontal[2];

        var cosAzimuth = Math.cos(azimuth);
        var sinAzimuth = Math.sin(azimuth);
        var cosAltitude = Math.cos(altitude);
        var sinAltitude = Math.sin(altitude);

        var sinDeclination = sinAltitude * sinLat + cosAltitude * cosLat * cosAzimuth;
        var cosDeclination = Math.sqrt(1 - sinDeclination * sinDeclination);  // Always positive, but sign has no effect on output (TODO: verify if parallactic angle is working correctly here)
        var declination = Math.asin(sinDeclination);
        
        var cosLha = (sinAltitude - sinDeclination * sinLat) / (cosDeclination * cosLat);
        var sinLha = -sinAzimuth * cosAltitude / cosDeclination;
        var lha = Math.atan2(sinLha, cosLha); 
        if (lha < 0) {
            lha += TWO_PI;
        }
        var rightAscension = lst - lha;
        if (rightAscension < 0) {
            rightAscension += TWO_PI;
        } else if (rightAscension > TWO_PI) {
            rightAscension -= TWO_PI;
        }

        var parallacticAngle = Math.atan2(sinLha, cosDeclination * (sinLat / cosLat) - sinDeclination * cosLha);
        var equatorialRoll = roll - parallacticAngle;

        return [rightAscension, declination, equatorialRoll];
    }

    class CelestialOrthographicProjection extends OrthographicProjection {
        /*
        Orthographic projection of celestial objects given in equatorial coordinate system

        Takes RA/dec coordinates in radians. Notes:
        - RA/dec is reversed from lat/long
        - RA has a different range than longitude [0, 2 * pi) vs. [-pi, pi)
        - x needs to be reversed, since we're looking from the inside of the sphere out
        */
        function initialize(center as Equatorial, radius as Float, options as {
                :rotation as Radians}) {
            /*
            :param center: Center of projection
            :param radius: Scale of projection in meters
            :param rotation: Rotation of projection in radians from N
            :return: Projected point, if in the front-facing hemisphere.
            */
            OrthographicProjection.initialize([center[1], center[0]], radius, options);
        }

        function setCenter(value as [Numeric, Numeric]) as Void {
            OrthographicProjection.setCenter([value[1], value[0]]);
        }

        function project(position as [Numeric, Numeric]) as Graphics.Point2D? {
            /*
            Apply projection. Points in the opposite hemisphere will be clipped (return null).

            :param position: Position in geodetic (lat/long) degree coordinates.
            :return: Projected point, if in the front-facing hemisphere.
            */
            var result = OrthographicProjection.project([position[1], position[0]]);
            if (result != null) {
                return [-result[0], result[1]];  // Flip left/right since we are looking from inside of celestial sphere out
            } else {
                return null;
            }
        }

        /*
        function getDomain() as [[Radians, Radians], [Radians, Radians]] {
            //
            Get domain of this projection

            :return:
                [0]: Right ascension min/max
                [1]: Declination min/max
            //
            var domain = OrthographicProjection.getDomain();

            var decDomain = domain[0];
            var raDomain = domain[1];
            var raMin = raDomain[0];
            if (raMin < 0) {
                raMin += TWO_PI;
            }
            var raMax = raDomain[1];
            if (raMax < 0) {
                raMax += TWO_PI;
            }
            
            return [[raMin, raMax], decDomain] as [[Radians, Radians], [Radians, Radians]];
        }
        */

        function toString() as String {
            var centerEquatorial = [_center[1], _center[0]];
            return "NavUtils.CelestialOrthographicProjection{" +
                "center=" + centerEquatorial.toString() + "," +
                "radius=" + _radius.toString() + "," +
                "rotation=" + _rotation.toString() + "}";
        }
    }

    (:test)
    function testGetSiderealTime(logger as Test.Logger) as Boolean {
        // Unit tests for getSiderealTime() function
        var tests = [
            [
                Time.Gregorian.moment({:year => 2000, :month => 1, :day => 1, :hour => 12, :minute => 0, :second => 0}),
                0.0,
                18.697375 * TWO_PI / 24.0,  // Hours
            ],
            [
                Time.Gregorian.moment({:year => 2009, :month => 7, :day => 22, :hour => 5, :minute => 9, :second => 50}),
                172.793055 * TWO_PI / 360.0,  // Degrees
                12.68964 * TWO_PI / 24.0,  // Hours
            ],
            [
                Time.Gregorian.moment({:year => 2023, :month => 4, :day => 18, :hour => 0, :minute => 50, :second => 0}),
                -73.7117 * TWO_PI / 360.0,  // Degrees
                9.64520786 * TWO_PI / 24.0,  // Hours
            ],
        ];

        for (var i = 0; i < tests.size(); i++) {
            var test = tests[i];
            var currentTime = test[0];
            var longitude = test[1];
            var expected = test[2];
            System.println("Test -- Current time: " + Time.Gregorian.utcInfo(currentTime, Time.FORMAT_SHORT) + ", longitude: " + longitude.toString());
            var actual = getSiderealTime(currentTime, longitude);
            System.println("Expected: " + expected.toString() + ", Actual: " + actual.toString());
            TestUtils.assertFloatEqual(actual, expected, {:tol => 1e-4});
        }

        return true;
    }

    (:test)
    function testEquatorialToHorizontalCoords(logger as Test.Logger) as Boolean {
        // Unit tests for equatorialToHorizontalCoords() function
        var tests = [
            // Equatorial value of zenith at sidereal origin time
            [
                [18.697375 * TWO_PI / 24.0, 0.0],  // Equatorial
                Time.Gregorian.moment({:year => 2000, :month => 1, :day => 1, :hour => 12, :minute => 0, :second => 0}),
                [0.0, 0.0] as LatLong,  // Location
                [0.0, 90.0 * TWO_PI / 360.0],  // Expected result: Horizontal (note: RA is not well-defined here)
            ],
            // Vary time
            [
                [18.697375 * TWO_PI / 24.0, 0.0],  // Equatorial
                Time.Gregorian.moment({:year => 2001, :month => 7, :day => 1, :hour => 12, :minute => 0, :second => 0}),
                [0.0, 0.0] as LatLong,  // Location
                [270.10 * TWO_PI / 360.0, -89.13 * TWO_PI / 360.0],  // Expected result: Horizontal 
            ],
            // Vary latitude
            [
                [18.697375 * TWO_PI / 24.0, 0.0],  // Equatorial
                Time.Gregorian.moment({:year => 2000, :month => 1, :day => 1, :hour => 12, :minute => 0, :second => 0}),
                [45.0, 0.0] as LatLong,  // Location
                [180.0 * TWO_PI / 360.0, 45.0 * TWO_PI / 360.0],  // Expected result: Horizontal
            ],
            [
                [18.697375 * TWO_PI / 24.0, 0.0],  // Equatorial
                Time.Gregorian.moment({:year => 2000, :month => 1, :day => 1, :hour => 12, :minute => 0, :second => 0}),
                [-30.0, 0.0] as LatLong,  // Location
                [0.0 * TWO_PI / 360.0, 60.0 * TWO_PI / 360.0],  // Expected result: Horizontal
            ],
            // Vary longitude
            [
                [18.697375 * TWO_PI / 24.0, 0.0],  // Equatorial
                Time.Gregorian.moment({:year => 2000, :month => 1, :day => 1, :hour => 12, :minute => 0, :second => 0}),
                [0.0, -120.0] as LatLong,  // Location
                [90.0 * TWO_PI / 360.0, -30.0 * TWO_PI / 360.0],  // Expected result: Horizontal
            ],
            [
                [18.697375 * TWO_PI / 24.0, 0.0],  // Equatorial
                Time.Gregorian.moment({:year => 2000, :month => 1, :day => 1, :hour => 12, :minute => 0, :second => 0}),
                [0.0, 15.0] as LatLong,  // Location
                [270.0 * TWO_PI / 360.0, 75.0 * TWO_PI / 360.0],  // Expected result: Horizontal
            ],
            // Vary declination of star
            [
                [18.697375 * TWO_PI / 24.0, 45.0 * TWO_PI / 360.0],  // Equatorial
                Time.Gregorian.moment({:year => 2000, :month => 1, :day => 1, :hour => 12, :minute => 0, :second => 0}),
                [0.0, 0.0] as LatLong,  // Location
                [0.0, 45.0 * TWO_PI / 360.0],  // Expected result: Horizontal
            ],
            [
                [18.697375 * TWO_PI / 24.0, -89.0 * TWO_PI / 360.0],  // Equatorial
                Time.Gregorian.moment({:year => 2000, :month => 1, :day => 1, :hour => 12, :minute => 0, :second => 0}),
                [0.0, 0.0] as LatLong,  // Location
                [180.0 * TWO_PI / 360.0, 1.0 * TWO_PI / 360.0],  // Expected result: Horizontal
            ],
            // Vary right ascension of star
            [
                [12.697375 * TWO_PI / 24.0, 0.0],  // Equatorial
                Time.Gregorian.moment({:year => 2000, :month => 1, :day => 1, :hour => 12, :minute => 0, :second => 0}),
                [0.0, 0.0] as LatLong,  // Location
                [270.0 * TWO_PI / 360.0, 0.0 * TWO_PI / 360.0],  // Expected result: Horizontal
            ],
            [
                [6.697375 * TWO_PI / 24.0, 0.0],  // Equatorial
                Time.Gregorian.moment({:year => 2000, :month => 1, :day => 1, :hour => 12, :minute => 0, :second => 0}),
                [0.0, 0.0] as LatLong,  // Location
                [0.0 * TWO_PI / 360.0, -90.0 * TWO_PI / 360.0],  // Expected result: Horizontal
            ],
            [
                [21.697375 * TWO_PI / 24.0, 0.0],  // Equatorial
                Time.Gregorian.moment({:year => 2000, :month => 1, :day => 1, :hour => 12, :minute => 0, :second => 0}),
                [0.0, 0.0] as LatLong,  // Location
                [90.0 * TWO_PI / 360.0, 45.0 * TWO_PI / 360.0],  // Expected result: Horizontal
            ],
            // Sample values from http://xjubier.free.fr/en/site_pages/astronomy/coordinatesConverter.html
            [
                [8.113925 * TWO_PI / 24.0, 20.246433 * TWO_PI / 360.0],  // Equatorial
                Time.Gregorian.moment({:year => 2009, :month => 7, :day => 22, :hour => 5, :minute => 9, :second => 50}),
                [6.053055, 172.793055] as LatLong,  // Location
                [289.40 * TWO_PI / 360.0, 22.24 * TWO_PI / 360.0],  // Expected result: Horizontal
            ],
            // Random values
            [
                [5.0 * TWO_PI / 24.0, -49.0 * TWO_PI / 360.0],  // Equatorial
                Time.Gregorian.moment({:year => 2005, :month => 11, :day => 9, :hour => 7, :minute => 13, :second => 55}),
                [-61.0, 129.0] as LatLong,  // Location
                [158.49 * TWO_PI / 360.0, 22.79 * TWO_PI / 360.0],  // Expected result: Horizontal
            ],
        ];

        for (var i = 0; i < tests.size(); i++) {
            var test = tests[i];
            var equatorial = test[0];
            var currentTime = test[1];
            var location = test[2];
            var expected = test[3];
            System.println("Test -- Equatorial coords: " + equatorial.toString() + ", current time: " + Time.Gregorian.utcInfo(currentTime, Time.FORMAT_SHORT) + ", location: " + location.toString());
            var actual = equatorialToHorizontalCoords(equatorial, currentTime, location);
            System.println("Expected: " + expected.toString() + ", Actual: " + actual.toString());
            TestUtils.assertFloatEqual(actual, expected, {:tol => 5e-3});  // Can probably tighten with proper adjustments to calculations
        }

        return true;
    }

    (:test)
    function testHorizontalToEquatorialCoords(logger as Test.Logger) as Boolean {
        // Unit tests for horizontalToEquatorialAttitude() function, without treatment of roll
        var tests = [
            // Equatorial value of zenith at sidereal origin time
            [
                [0.0, 90.0 * TWO_PI / 360.0],  // Horizontal (note: RA is not well-defined here)
                Time.Gregorian.moment({:year => 2000, :month => 1, :day => 1, :hour => 12, :minute => 0, :second => 0}),
                [0.0, 0.0] as LatLong,  // Location
                [18.697375 * TWO_PI / 24.0, 0.0],  // Expected result: Equatorial
            ],
            // Vary time
            [
                [270.10 * TWO_PI / 360.0, -89.13 * TWO_PI / 360.0],  // Horizontal 
                Time.Gregorian.moment({:year => 2001, :month => 7, :day => 1, :hour => 12, :minute => 0, :second => 0}),
                [0.0, 0.0] as LatLong,  // Location
                [18.697375 * TWO_PI / 24.0, 0.0],  // Expected result: Equatorial
            ],
            // Vary latitude
            [
                [180.0 * TWO_PI / 360.0, 45.0 * TWO_PI / 360.0],  // Horizontal
                Time.Gregorian.moment({:year => 2000, :month => 1, :day => 1, :hour => 12, :minute => 0, :second => 0}),
                [45.0, 0.0] as LatLong,  // Location
                [18.697375 * TWO_PI / 24.0, 0.0],  // Expected result: Equatorial
            ],
            [
                [0.0 * TWO_PI / 360.0, 60.0 * TWO_PI / 360.0],  // Horizontal
                Time.Gregorian.moment({:year => 2000, :month => 1, :day => 1, :hour => 12, :minute => 0, :second => 0}),
                [-30.0, 0.0] as LatLong,  // Location
                [18.697375 * TWO_PI / 24.0, 0.0],  // Expected result: Equatorial
            ],
            // Vary longitude
            [
                [90.0 * TWO_PI / 360.0, -30.0 * TWO_PI / 360.0],  // Horizontal
                Time.Gregorian.moment({:year => 2000, :month => 1, :day => 1, :hour => 12, :minute => 0, :second => 0}),
                [0.0, -120.0] as LatLong,  // Location
                [18.697375 * TWO_PI / 24.0, 0.0],  // Expected result: Equatorial
            ],
            [
                [270.0 * TWO_PI / 360.0, 75.0 * TWO_PI / 360.0],  // Horizontal
                Time.Gregorian.moment({:year => 2000, :month => 1, :day => 1, :hour => 12, :minute => 0, :second => 0}),
                [0.0, 15.0] as LatLong,  // Location
                [18.697375 * TWO_PI / 24.0, 0.0],  // Expected result: Equatorial
            ],
            // Vary declination of star
            [
                [0.0, 45.0 * TWO_PI / 360.0],  // Horizontal
                Time.Gregorian.moment({:year => 2000, :month => 1, :day => 1, :hour => 12, :minute => 0, :second => 0}),
                [0.0, 0.0] as LatLong,  // Location
                [18.697375 * TWO_PI / 24.0, 45.0 * TWO_PI / 360.0],  // Expected result: Equatorial
            ],
            [
                [180.0 * TWO_PI / 360.0, 1.0 * TWO_PI / 360.0],  // Horizontal
                Time.Gregorian.moment({:year => 2000, :month => 1, :day => 1, :hour => 12, :minute => 0, :second => 0}),
                [0.0, 0.0] as LatLong,  // Location
                [18.697375 * TWO_PI / 24.0, -89.0 * TWO_PI / 360.0],  // Expected result: Equatorial
            ],
            // Vary right ascension of star
            [
                [270.0 * TWO_PI / 360.0, 0.0 * TWO_PI / 360.0],  // Horizontal
                Time.Gregorian.moment({:year => 2000, :month => 1, :day => 1, :hour => 12, :minute => 0, :second => 0}),
                [0.0, 0.0] as LatLong,  // Location
                [12.697375 * TWO_PI / 24.0, 0.0],  // Expected result: Equatorial
            ],
            [
                [0.0 * TWO_PI / 360.0, -90.0 * TWO_PI / 360.0],  // Horizontal
                Time.Gregorian.moment({:year => 2000, :month => 1, :day => 1, :hour => 12, :minute => 0, :second => 0}),
                [0.0, 0.0] as LatLong,  // Location
                [6.697375 * TWO_PI / 24.0, 0.0],  // Expected result: Equatorial
            ],
            [
                [90.0 * TWO_PI / 360.0, 45.0 * TWO_PI / 360.0],  // Horizontal
                Time.Gregorian.moment({:year => 2000, :month => 1, :day => 1, :hour => 12, :minute => 0, :second => 0}),
                [0.0, 0.0] as LatLong,  // Location
                [21.697375 * TWO_PI / 24.0, 0.0],  // Expected result: Equatorial
            ],
            // Sample values from http://xjubier.free.fr/en/site_pages/astronomy/coordinatesConverter.html
            [
                [289.40 * TWO_PI / 360.0, 22.24 * TWO_PI / 360.0],  // Horizontal
                Time.Gregorian.moment({:year => 2009, :month => 7, :day => 22, :hour => 5, :minute => 9, :second => 50}),
                [6.053055, 172.793055] as LatLong,  // Location
                [8.113925 * TWO_PI / 24.0, 20.246433 * TWO_PI / 360.0],  // Expected result: Equatorial
            ],
            // Random values
            [
                [158.49 * TWO_PI / 360.0, 22.79 * TWO_PI / 360.0],  // Horizontal
                Time.Gregorian.moment({:year => 2005, :month => 11, :day => 9, :hour => 7, :minute => 13, :second => 55}),
                [-61.0, 129.0] as LatLong,  // Location
                [5.0 * TWO_PI / 24.0, -49.0 * TWO_PI / 360.0],  // Expected result: Equatorial
            ],
        ];

        for (var i = 0; i < tests.size(); i++) {
            var test = tests[i];
            var horizontal = test[0];
            var currentTime = test[1];
            var location = test[2];
            var expected = test[3];
            System.println("Test -- Horizontal coords: " + horizontal.toString() + ", current time: " + Time.Gregorian.utcInfo(currentTime, Time.FORMAT_SHORT) + ", location: " + location.toString());
            horizontal.add(0.0);
            var actual = horizontalToEquatorialAttitude(horizontal, currentTime, location).slice(0, 2);
            System.println("Expected: " + expected.toString() + ", Actual: " + actual.toString());
            TestUtils.assertFloatEqual(actual, expected, {:tol => 5e-3});  // Can probably tighten with proper adjustments to calculations
        }

        return true;
    }
}
