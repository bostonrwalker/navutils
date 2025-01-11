import Toybox.Lang;
import Toybox.Time;
import Toybox.Position;
import Toybox.Math;
import Toybox.Test;


/*******************************************************************************
Main NavUtils module
********************************************************************************
Functions for working with headings in Degrees, DMS, Radians, and Mils

Created: 11 Jan 2025 by Boston W
*******************************************************************************/


module NavUtils {
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

    function decimalDegreesToDMS(degrees as DecimalDegrees) as DMS {
        /*
        Convert decimal degrees to integer degrees, minutes, seconds

        Return values are rounded to the nearest second.

        :param degrees: Decimal degrees. Must be non-negative, i.e. in range [0, infinity).
        :return: Tuple [degrees, minutes, seconds]
        */
        if (degrees < 0) {
            throw new Lang.InvalidValueException(
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
        var minAccelerometer = getDefault(options, :minAccelerometer, 750.0) as Float;
        var minMagnetometer = getDefault(options, :minMagnetometer, 100.0) as Float;
        var minAngleDegrees = getDefault(options, :minAngle, 8.0) as Numeric;

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

    function applyMagneticDeclination(heading as Radians?, magDec as Radians?) as Radians? {
        /*
        Subtract magnetic declination from magnetic N heading

        :param heading: Heading from magnetic N in rads
        :param magDec: Mag dec in degrees. Per convention W is positive and E is negative.
        */
        return addRadians(heading, -degreesToRads(magDec));
    }


    (:test)
    function testAddRadians(logger as Logger) as Boolean {
        assertFloatEqual(addRadians(0.0, Math.PI / 2), Math.PI / 2, {:tol => 1e-6});
        assertFloatEqual(addRadians(0.0, -Math.PI / 2), 3 * Math.PI / 2, {:tol => 1e-6});
        assertFloatEqual(addRadians(0.0, 2 * Math.PI), 0.0, {:tol => 1e-6});
        assertFloatEqual(addRadians(0.0, -2 * Math.PI), 0.0, {:tol => 1e-6});
        assertFloatEqual(addRadians(Math.PI, Math.PI), 0.0, {:tol => 1e-6});
        assertFloatEqual(addRadians(Math.PI / 2, -Math.PI / 2), 0.0, {:tol => 1e-6});
        return true;
    }


    (:test)
    function testGetBearingFromMagneticNorth(logger as Logger) as Boolean {

        // Test scenario 1: Magnetic field of 400 uT parallel to ground

        // --- FACING N --- //
        // Looking down at device
        assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, -1000.0], [0.0, 400.0, 0.0], {}), 0.0, {:tol => 1e-6});

        // Bring the device to eye level
        assertFloatEqual(getBearingFromMagneticNorth([0.0, -1000.0, 0.0], [0.0, 0.0, -400.0], {}), 0.0, {:tol => 1e-6});

        // Tilt it 45* left or right
        assertFloatEqual(getBearingFromMagneticNorth([-707.0, -707.0, 0.0], [0.0, 0.0, -400.0], {}), 0.0, {:tol => 1e-6});
        assertFloatEqual(getBearingFromMagneticNorth([707.0, -707.0, 0.0], [0.0, 0.0, -400.0], {}), 0.0, {:tol => 1e-6});

        // Looking straight up at device
        assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, 1000.0], [0.0, -400.0, 0.0], {}), 0.0, {:tol => 1e-6});

        // --- FACING NE --- //
        // Looking down at device
        assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, -1000.0], [-283.0, 283.0, 0.0], {}), Math.PI / 4, {:tol => 1e-6});

        // --- FACING E --- //
        // Looking down at device
        assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, -1000.0], [-400.0, 0.0, 0.0], {}), Math.PI / 2, {:tol => 1e-6});

        // Bring the device to eye level
        assertFloatEqual(getBearingFromMagneticNorth([0.0, -1000.0, 0.0], [-400.0, 0.0, 0.0], {}), Math.PI / 2, {:tol => 1e-6});

        // Tilt it 45* left or right
        assertFloatEqual(getBearingFromMagneticNorth([-707.0, -707.0, 0.0], [-283.0, 283.0, 0.0], {}), Math.PI / 2, {:tol => 1e-6});
        assertFloatEqual(getBearingFromMagneticNorth([707.0, -707.0, 0.0], [-283.0, -283.0, 0.0], {}), Math.PI / 2, {:tol => 1e-6});

        // Looking straight up at device
        assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, 1000.0], [-400.0, 0.0, 0.0], {}), Math.PI / 2, {:tol => 1e-6});

        // --- FACING SE --- //
        // Looking down at device
        assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, -1000.0], [-283.0, -283.0, 0.0], {}), 3 * Math.PI / 4, {:tol => 1e-6});

        // --- FACING S --- //
        // Looking down at device
        assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, -1000.0], [0.0, -400.0, 0.0], {}), Math.PI, {:tol => 1e-6});

        // Bring the device to eye level
        assertFloatEqual(getBearingFromMagneticNorth([0.0, -1000.0, 0.0], [0.0, 0.0, 400.0], {}), Math.PI, {:tol => 1e-6});

        // Tilt it 45* left or right
        assertFloatEqual(getBearingFromMagneticNorth([-707.0, -707.0, 0.0], [0.0, 0.0, 400.0], {}), Math.PI, {:tol => 1e-6});
        assertFloatEqual(getBearingFromMagneticNorth([707.0, -707.0, 0.0], [0.0, 0.0, 400.0], {}), Math.PI, {:tol => 1e-6});

        // Looking straight up at device
        assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, 1000.0], [0.0, 400.0, 0.0], {}), Math.PI, {:tol => 1e-6});

        // --- FACING SW --- //
        // Looking down at device
        assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, -1000.0], [283.0, -283.0, 0.0], {}), 5 * Math.PI / 4, {:tol => 1e-6});

        // --- FACING W --- //
        // Looking down at device
        assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, -1000.0], [400.0, 0.0, 0.0], {}), 3 * Math.PI / 2, {:tol => 1e-6});

        // Bring the device to eye level
        assertFloatEqual(getBearingFromMagneticNorth([0.0, -1000.0, 0.0], [400.0, 0.0, 0.0], {}), 3 * Math.PI / 2, {:tol => 1e-6});

        // Tilt it 45* left or right
        assertFloatEqual(getBearingFromMagneticNorth([-707.0, -707.0, 0.0], [283.0, -283.0, 0.0], {}), 3 * Math.PI / 2, {:tol => 1e-6});
        assertFloatEqual(getBearingFromMagneticNorth([707.0, -707.0, 0.0], [283.0, 283.0, 0.0], {}), 3 * Math.PI / 2, {:tol => 1e-6});

        // Looking straight up at device
        assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, 1000.0], [400.0, 0.0, 0.0], {}), 3 * Math.PI / 2, {:tol => 1e-6});

        // --- FACING NW --- //
        // Looking down at device
        assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, -1000.0], [283.0, 283.0, 0.0], {}), 7 * Math.PI / 4, {:tol => 1e-6});


        // Test scenario 2: Magnetic field of 500 uT running down into ground at 53.13 degrees (3-4-5 triangle)

        // Facing N, looking down at device
        assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, -1000.0], [0.0, 300.0, -400.0], {}), 0.0, {:tol => 1e-6});

        // Facing W, looking across at device
        assertFloatEqual(getBearingFromMagneticNorth([0.0, -1000.0, 0.0], [-300.0, -400.0, 0.0], {}), Math.PI / 2, {:tol => 1e-6});

        // Facing S, looking straight up at device
        assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, 1000.0], [0.0, 300.0, 400.0], {}), Math.PI, {:tol => 1e-6});


        // Test scenario 3: Magnetic field aligned with gravity
        assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, -1000.0], [0.0, 0.0, -500.0], {}), null, {});

        // Test scenario 4: Weak magnetic field
        assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, -1000.0], [0.0, 50.0, 0.0], {}), null, {});

        // Test scenario 5: Weak gravity
        assertFloatEqual(getBearingFromMagneticNorth([0.0, 0.0, -500.0], [0.0, 300.0, 0.0], {}), null, {});

        return true;
    }
}