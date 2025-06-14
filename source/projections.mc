import Toybox.Lang;
using Toybox.Graphics;
using Toybox.Math;


/*******************************************************************************
NavUtils.Projections module
********************************************************************************
Functions for working with map projections

Created: 4 Feb 2025 by Boston W
*******************************************************************************/

module NavUtils {
    /*******************************************************************************
    Typedefs
    *******************************************************************************/

    typedef Projection as interface {
        function project(position as NavUtils.LatLong) as Graphics.Point2D?;
    };

    class OrthographicProjection {  // implements Projection
        /*
        Orthographic map projection
        */
        private var _center as NavUtils.LatLong;
        private var _scale as NavUtils.Meters;
        private var _rotation as Radians;

        private var _cosPhi0 as Float;
        private var _sinPhi0 as Float;
        private var _lambda0 as Radians;
        private var _scaleFactor as NavUtils.Meters;

        function initialize(center as NavUtils.LatLong, scale as NavUtils.Meters, options as {
                :rotation as Radians}) {
            /*
            :param center: Center of projection
            :param scale: Scale of projection in meters
            :param rotation: Rotation of projection in radians from N
            :return: Projected point, if in the front-facing hemisphere.
            */
            _center = center;
            _scale = scale;
            _rotation = Utils.getDefault(options, :rotation, 0.0f) as Radians;

            var phi0 = degreesToRads(center[0]);
            _cosPhi0 = Math.cos(phi0);
            _sinPhi0 = Math.sin(phi0);
            _lambda0 = degreesToRads(center[1]);
            _scaleFactor = R / scale;
        }

        function setRotation(value as Radians) as Void {
            _rotation = value;
        }

        function project(position as NavUtils.LatLong) as Graphics.Point2D? {
            /*
            Apply projection. Points in the opposite hemisphere will be clipped (return null).

            :param position: Position in geodetic (lat/long) degree coordinates.
            :return: Projected point, if in the front-facing hemisphere.
            */
            // Recenter point and transform to radians
            var phi = degreesToRads(position[0]);
            var lambda = degreesToRads(position[1]) - _lambda0;  // Centered on lambda0

            var cosPhi = Math.cos(phi);
            var sinPhi = Math.sin(phi);
            var cosLambda = Math.cos(lambda);

            var cosC = _sinPhi0 * sinPhi + _cosPhi0 * cosPhi * cosLambda;  // Cosine of angular distance c
            if (cosC > 0) {
                // Point is in the correct hemisphere
                var sinC = Math.sqrt(1 - cosC * cosC);
                var r = sinC / _radius;
                if (r < 1) {
                    // Point is within view
                    var sinLambda = Math.sin(lambda);
                    var x = cosPhi * sinLambda; 
                    var y = _cosPhi0 * sinPhi - _sinPhi0 * cosPhi * cosLambda;
                    var theta = Math.atan2(x, -y) + _rotation;  // Degrees clockwise from N
                    return [r * Math.sin(theta), -r * Math.cos(theta)];
                }
            }
            return null;
        }

        /*
        function getDomain() as [[Radians, Radians], [Radians, Radians]] {
            //
            Get domain of this projection

            :return:
                [0]: Phi (latitude) min/max
                [1]: Lambda (longitude) min/max
            //
            var phiMin = addRadians(_lambda0, Math.asin(-_radius / _cosPhi0));
            var phiMax = addRadians(_lambda0, Math.asin(_radius / _cosPhi0));

            var t = _radius / (_cosPhi0 * _sinPhi0);
            var lambdaMin = Math.acos(1 + t);
            var lambdaMax = Math.acos(1 - t);

            return [[phiMin, phiMax], [lambdaMin, lambdaMax]] as [[Radians, Radians], [Radians, Radians]];
        }
        */

        function toString() as String {
            return "NavUtils.OrthographicProjection{" +
                "center=" + _center.toString() + "," +
                "scale=" + _scale.toString() + "," +
                "rotation=" + _rotation.toString() + "}";
        }
    }
}