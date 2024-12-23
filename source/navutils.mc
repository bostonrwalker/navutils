import Toybox.Lang;
import Toybox.Time;
import Toybox.Position;
import Toybox.Math;


const TWO_PI = 2 * Math.PI as Float;


module NavUtils {

    function addRadians(angle as Float, delta as Float) as Float {
        /*
        Add radians to a base angle, while keeping in [0, 2 pi) range

        :param angle: Angle in radians. Must be in range [0, 2 * pi)
        :param delta: Differential angle in radians. Must be in range [-2 * pi, 2 * pi)
        :return: (a + b) mod 2 * pi, in range [0, 2 * pi)
        */
        var result = angle + delta;
        if (result < 0) {
            result += TWO_PI;
        } else if (result >= TWO_PI) {
            result -= TWO_PI;
        }
        return result;
    }

    function radsToMils(radians as Numeric?) as Number? {
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

    function milsToRads(mils as Number?) as Float? {
        // Convert radians to mils
        if (mils == null) {
            return null;
        } else {
            return mils * TWO_PI / 6400.0;
        }
    }

    function getBearingFromMagneticNorth(a as Array<Numeric>, m as Array<Numeric>, options as {
            :minAccelerometer as Numeric, :minMagnetometer as Numeric, :minAngle as Numeric}) as Float? {
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
        :return: Bearing in radians (if defined)
        */
        var minAccelerometer = Codex.Utils.getDefault(options, :minAccelerometer, 750.0) as Float;
        var minMagnetometer = Codex.Utils.getDefault(options, :minMagnetometer, 100.0) as Float;
        var minAngleDegrees = Codex.Utils.getDefault(options, :minAngle, 8.0) as Numeric;

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

        mLatX /= magMLat;
        mLatY /= magMLat;
        mLatZ /= magMLat;

        // Lateral component of unit reference vector ([1, 0, 0])
        var rLatX = 1.0 - ax * ax;
        var rLatY = -ax * ay;
        var rLatZ = -ax * az;

        var magRLat = Math.sqrt(rLatX * rLatX + rLatY * rLatY + rLatZ * rLatZ);

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
        return Math.atan2(-cosTheta, sinTheta);
    }
}