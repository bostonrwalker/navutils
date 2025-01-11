import Toybox.Lang;
using Toybox.Math;
using Toybox.Test;
using Toybox.System;


/*******************************************************************************
NavUtils.Mgrs module
********************************************************************************
Functions for working with UTM and MGRS

Prior art:
https://github.com/OSGeo/gdal/
https://github.com/Turbo87/utm/

Created: 11 Jan 2025 by Boston W
*******************************************************************************/

/*
WGS84 model
*/

// Spheroid parameters
const R = 6378137.0;
const K0 = 0.9996;

const E = 0.00669438;
const E2 = E * E;
const E3 = E2 * E;
const E_P2 = E / (1.0 - E);

// Precomputed constants
const SQRT_E = Math.sqrt(1.0 - E);
const _E = (1.0 - SQRT_E) / (1.0 + SQRT_E);
const _E2 = _E * _E;
const _E3 = _E2 * _E;
const _E4 = _E3 * _E;
const _E5 = _E4 * _E;

const M1 = (1.0 - E / 4.0 - 3.0 * E2 / 64.0 - 5.0 * E3 / 256.0);
const M2 = (3.0 * E / 8.0 + 3.0 * E2 / 32.0 + 45.0 * E3 / 1024.0);
const M3 = (15.0 * E2 / 256.0 + 45.0 * E3 / 1024.0);
const M4 = (35.0 * E3 / 3072.0);

const P2 = (3.0 / 2.0 * _E - 27.0 / 32.0 * _E3 + 269.0 / 512.0 * _E5);
const P3 = (21.0 / 16.0 * _E2 - 55.0 / 32.0 * _E4);
const P4 = (151.0 / 96.0 * _E3 - 417.0 / 128.0 * _E5);
const P5 = (1097.0 / 512.0 * _E4);


typedef LatitudeBand as [Number, Float, Float];

const LATITUDE_BANDS = {
    'C' => [1100000, -72.0, -80.5],
    'D' => [2000000, -64.0, -72.0],
    'E' => [2800000, -56.0, -64.0],
    'F' => [3700000, -48.0, -56.0],
    'G' => [4600000, -40.0, -48.0],
    'H' => [5500000, -32.0, -40.0],
    'J' => [6400000, -24.0, -32.0],
    'K' => [7300000, -16.0, -24.0],
    'L' => [8200000, -8.0, -16.0],
    'M' => [9100000, 0.0, -8.0],
    'N' => [0, 8.0, 0.0],
    'P' => [800000, 16.0, 8.0],
    'Q' => [1700000, 24.0, 16.0],
    'R' => [2600000, 32.0, 24.0],
    'S' => [3500000, 40.0, 32.0],
    'T' => [4400000, 48.0, 40.0],
    'U' => [5300000, 56.0, 48.0],
    'V' => [6200000, 64.0, 56.0],
    'W' => [7000000, 72.0, 64.0],
    'X' => [7900000, 84.5, 72.0],
};


module NavUtils {

    (:Mgrs)
    module Mgrs {
        /*
        UTM type:

        [0]: UTM zone (e.g. "18T")
        [1]: UTM easting in meters
        [2]: UTM northing in meters
        */
        typedef UTM as [String, Number, Number];

        /*
        MGRS type:

        [0]: UTM zone (e.g. "18T")
        [1]: MGRS grid reference (e.g. "UV")
        [2]: MGRS easting (1 meter precision)
        [3]: MGRS northing (1 meter precision)
        */
        typedef MGRS as [String, String, Number, Number];

        function _validateUTMZone(zone as String) as Void {
            /*
            Validate that UTM zone looks legit

            :raise InvalidValueException: If UTM zone is invalid
            */

            var zoneNumber = zone.substring(0, 2).toNumber();
            var zoneLetter = zone.substring(2, 3).toCharArray()[0];

            if (zoneLetter < 'C' || zoneLetter > 'X' || zoneLetter == 'I' || zoneLetter == 'O' ||  // Valid zone letter range
                zoneNumber < 1 || zoneNumber > 60 || // Valid zone number range
                (zoneLetter == 'X' && (zoneNumber == 32 || zoneNumber == 34 || zoneNumber == 36))) {  // Exceptions
                throw new InvalidValueException(
                    "Invalid UTM zone: " + zone.toString());
            }

            if (zoneLetter == 'A' || zoneLetter == 'B' || zoneLetter == 'Y' || zoneLetter == 'Z') {
                // Polar regions need to be handled in UPS (not supported)
                throw new InvalidValueException(
                    "Unsupported UTM zone: " + zone);
            }
        }

        function _validateUTM(utm as UTM) as Void {
            /*
            Validate that UTM coordinates look legit

            :raise InvalidValueException: If UTM coordinates are invalid
            */
            var zone = utm[0];
            var easting = utm[1];
            var northing = utm[2];

            _validateUTMZone(zone);

            if (easting < 100000 || easting >= 1000000 || northing < 0 || northing >= 10000000) {
                throw new InvalidValueException(
                    "UTM coordinates out-of-bounds: " + utm.toString());
            }
        }

        function isUTMValid(utm as UTM) as Boolean {
            try {
                _validateUTM(utm);
                return true;
            } catch (e) {
                return false;
            }
        }

        function utmToWGS84(utm as UTM) as LatLong {
            /*
            Convert UTM to WGS84 lat/long (geodetic) coordinates
            */

            _validateUTM(utm);

            var zone = utm[0];
            var easting = utm[1];
            var northing = utm[2];

            var zoneNumber = zone.substring(0, 2).toNumber();
            var zoneLetter = zone.substring(2, 3).toCharArray()[0];

            var x = easting - 500000;
            var y;
            if (zoneLetter >= 'N') {
                y = northing;
            } else {
                y = northing - 10000000;
            }

            var m = y / K0;
            var mu = m / (R * M1);

            var pRad = mu +
                P2 * Math.sin(2.0 * mu) +
                P3 * Math.sin(4.0 * mu) +
                P4 * Math.sin(6.0 * mu) +
                P5 * Math.sin(8.0 * mu);

            var pSin = Math.sin(pRad);
            var pSin2 = pSin * pSin;

            var pCos = Math.cos(pRad);
            var pCos2 = pCos * pCos;

            var pTan = pSin / pCos;
            var pTan2 = pTan * pTan;
            var pTan4 = pTan2 * pTan2;

            var ePSin = 1 - E * pSin2;
            var ePSin2Sqrt = Math.sqrt(1 - E * pSin2);

            var n = R / ePSin2Sqrt;
            var r = (1 - E) / ePSin;

            var c = E_P2 * pCos2;
            var c2 = c * c;

            var d = x / (n * K0);
            var d2 = d * d;
            var d3 = d2 * d;
            var d4 = d3 * d;
            var d5 = d4 * d;
            var d6 = d5 * d;

            var lat = pRad - (pTan / r) * (
                d2 / 2.0 -
                d4 / 24.0 * (5.0 + 3.0 * pTan2 + 10.0 * c - 4.0 * c2 - 9.0 * E_P2) +
                d6 / 720.0 * (61.0 + 90.0 * pTan2 + 298.0 * c + 45.0 * pTan4 - 252.0 * E_P2 - 3.0 * c2));

            var lon = (d -
                d3 / 6.0 * (1.0 + 2.0 * pTan2 + c) +
                d5 / 120.0 * (5.0 - 2.0 * c + 28.0 * pTan2 - 3.0 * c2 + 8.0 * E_P2 + 24.0 * pTan4)) / pCos;

            var zoneLon = (zoneNumber - 1) * Math.PI / 30.0 - Math.PI + Math.PI / 60.0;

            lon = addRadians(lon, zoneLon);  // [0, 2 * pi) range
            if (lon >= Math.PI) {
                lon -= TWO_PI;
            }

            return [lat * 180.0 / Math.PI, lon * 180.0 / Math.PI];
        }

        function _validateMGRS(mgrs as MGRS) as Void {
            /*
            Validate that MGRS coordinates look legit

            :raise InvalidValueException: If MGRS coordinates are invalid
            */
            var zone = mgrs[0];
            var gzd = mgrs[1];
            var easting = mgrs[2];
            var northing = mgrs[3];

            _validateUTMZone(zone);

            var zoneNumber = zone.substring(0, 2).toNumber();
            // var zoneLetter = zone.substring(2, 3).toCharArray()[0];

            /* 
            Check that the second letter of the MGRS string is within the range of valid second letter values.
            Also check that the third letter is valid.
            */
            var gzdLonMin;
            var gzdLonMax;
            if (zoneNumber % 3 == 1) {
                gzdLonMin = 'A';
                gzdLonMax = 'H';
            } else if (zoneNumber % 3 == 2) {
                gzdLonMin = 'J';
                gzdLonMax = 'R';
            } else {
                gzdLonMin = 'S';
                gzdLonMax = 'Z';
            }

            var gzdChars = gzd.toCharArray();
            var gzdLon = gzdChars[0];
            var gzdLat = gzdChars[1];
            if (gzdLon < gzdLonMin || gzdLon > gzdLonMax || gzdLat > 'V') {
                throw new InvalidValueException(
                    "Invalid grid zone designation: " + gzd);
            }

            if (easting < 0 || easting >= 100000 || northing < 0 || northing >= 100000) {
                throw new InvalidValueException(
                    "MGRS coordinates out-of-bounds: " + mgrs.toString());
            }
        }

        function isMGRSValid(mgrs as MGRS) as Boolean {
            try {
                _validateMGRS(mgrs);
                return true;
            } catch (e) {
                return false;
            }
        }

        function mgrsToUTM(mgrs as MGRS) as UTM {
            /*
            Convert an MGRS coordinate string to UTM projection (zone, hemisphere, easting and northing) coordinates
            according to the current ellipsoid parameters.

            :raise InvalidValueException: If MGRS coordinates are invalid
            */

            _validateMGRS(mgrs);

            var zone = mgrs[0];
            var gzd = mgrs[1];
            var easting = mgrs[2];
            var northing = mgrs[3];

            var zoneNumber = zone.substring(0, 2).toNumber();
            var zoneLetter = zone.substring(2, 3).toCharArray()[0];

            var gzdLonMin;
            if (zoneNumber % 3 == 1) {
                gzdLonMin = 'A';
            } else if (zoneNumber % 3 == 2) {
                gzdLonMin = 'J';
            } else {
                gzdLonMin = 'S';
            }

            var falseNorthing = (zoneNumber % 2) == 0 ? 1500000 : 0;

            /* Check that the second letter of the MGRS string is within
                * the range of valid second letter values
                * Also check that the third letter is valid */
            var gzdChars = gzd.toCharArray();
            var gzdLon = gzdChars[0];
            var gzdLat = gzdChars[1];

            // Calculate easting of MGRS grid
            var gridEasting = (gzdLon.toNumber() - gzdLonMin.toNumber() + 1) * 100000;
            if (gzdLonMin == 'J' && gzdLon > 'O') {
                gridEasting -= 100000;
            }

            // Calculate northing of MGRS grid
            var gzdLatIndex;  // Num zones N of false northing
            if (gzdLat <= 'I') {
                gzdLatIndex = gzdLat.toNumber() - 65;
            } else if (gzdLat <= 'O') {
                gzdLatIndex = gzdLat.toNumber() - 66;
            } else {
                gzdLatIndex = gzdLat.toNumber() - 67;
            }

            var gridNorthing = falseNorthing + 100000 * gzdLatIndex;
            if (gridNorthing >= 2000000) {
                gridNorthing -= 2000000;
            }

            // Note: "x - 65" = Convert ASCII char x to letter index

            var latitudeBand = LATITUDE_BANDS[zoneLetter];
            var minNorthing = latitudeBand[0];

            gridNorthing -= minNorthing % 2000000;  // Scaled min northing calculation
            if (gridNorthing < 0) {
                gridNorthing += 2000000;
            }
            gridNorthing += minNorthing;

            var utmEasting = gridEasting + easting;
            var utmNorthing = gridNorthing + northing;

            return [zone, utmEasting, utmNorthing];
        }

        function mgrsToWGS84(mgrs as MGRS) as LatLong {
            var utm = mgrsToUTM(mgrs);
            return utmToWGS84(utm);
        }

        /*
        function getGridConvergence(location as Position.Location) as Float {
            // Get UTM / MGRS grid convergence (difference between grid north and true north) at location
            // [True North] = [Grid North] + [Grid Convergence]
            var mgrs = location.toGeoString(Position.GEO_MGRS);
            var grid = mgrs.substring(0, 5);
            var easting = mgrs.substring(5, 10).asNumber();
            var northing = mgrs.substring(10, 15).asNumber();

            var testDistance = 10000.0;  // 10 km
            var testDirections = [0.0, Math.PI];  // N, S

            for (var i = 0; i < testDirections.size(); i++) {
                var testDirection = testDirections[i];
                var testLocation = location.getProjectedLocation(testDirection, 10000.0);
                var testMgrs = testLocation.toGeoString(Position.GEO_MGRS);
                if (testMgrs.substring(0, 5).equals(grid)) {
                    // We are still in the same MGRS grid, can do calculation
                    var testEasting = testMgrs.substring(5, 10).asNumber();
                    var testNorthing = testMgrs.substring(10, 15).asNumber();
                    var directionUTM = Math.atan2(testNorthing - northing, testEasting - easting);
                    var convergence = testDirection - directionUTM;
                    if (convergence > Math.PI) {
                        convergence -= 2.0 * Math.PI;
                    }
                    return convergence;
                }
            }

            // This should never happen - either of 10km N or 10km S should always be within the same grid
            throw InvalidValueException("");
        }
        */

        (:test)
        function testUTMToWGS84(logger as Test.Logger) as Boolean {
            // Test conversion of UTM coordinates to WGS84 geodetic
            var tests = [
                [["50Q", 207634, 2466491], [22.279327, 114.162809]],
                [["19T", 709131, 5057968], [45.643731, -66.316328]],
                [["34H", 257204, 6257124], [-33.798216, 18.377392]],
                [["32V", 257190, 6775213], [61.036652, 4.503014]],
                [["18M", 471443, 9986739], [-0.119979, -75.256633]],
            ];

            // Tolerance of 2e-5 is appox. equivalent to 1-2 meters, depending on where you are in the world
            var tolerance = 2e-5;

            for (var i = 0; i < tests.size(); i++) {
                var test = tests[i];
                var testCoords = test[0];
                var expected = test[1];
                var actual = utmToWGS84(testCoords);
                System.println("Test UTM: " + testCoords.toString());
                System.println("Expected: " + expected.toString() + ", Actual: " + actual.toString());
                assertFloatEqual(actual[0], expected[0], {:tol => tolerance});
                assertFloatEqual(actual[1], expected[1], {:tol => tolerance});
            }
            
            return true;
        }


        (:test)
        function testMGRSToUTM(logger as Test.Logger) as Boolean {
            // Test conversion of MGRS to UTM

            // Test expected vs. actual
            var tests = [
                [["50Q", "KK", 7634, 66491], ["50Q", 207634, 2466491]],
                [["19T", "GL", 9131, 57968], ["19T", 709131, 5057968]],
                [["34H", "BH", 57204, 57124], ["34H", 257204, 6257124]],
            ];

            for (var i = 0; i < tests.size(); i++) {
                var test = tests[i];
                var testCoords = test[0];
                var expected = test[1];
                var actual = mgrsToUTM(testCoords);
                System.println("Test MGRS: " + testCoords.toString());
                System.println("Expected: " + expected.toString() + ", Actual: " + actual.toString());
                Test.assertEqual(actual.toString(), expected.toString());
            }
            
            return true;
        }

        (:test)
        function testValidateUTM(logger as Test.Logger) as Boolean {
            // Test some invalid UTM coordinates and ensure that an exception is thrown
            var tests = [ 
                ["19T", 99999, 5000000],  // Easting out of range
                ["19T", 1000000, 5000000],
                ["19T", 500000, -1],  // Northing out of range
                ["19T", 500000, 10000000],
                ["31Z", 462935, 765000],  // Z (Antarctic zone) not supported
            ];

            for (var i = 0; i < tests.size(); i++) {
                var testCoords = tests[i];
                System.println("Test invalid UTM: " + testCoords.toString());
                var exception = false;
                try {
                    _validateUTM(testCoords);
                } catch (e) {
                    exception = true;
                }

                if (!exception) {
                    throw new Test.AssertException("Exception was not raised for invalid UTM!");
                }
            }

            return true;
        }

        (:test)
        function testValidateMGRS(logger as Test.Logger) as Boolean {
            // Test some invalid MGRS coordinates and ensure that an exception is thrown
            var tests = [
                ["18T", "UV", -1, 50000],  // Easting out of range
                ["18T", "UV", 100000, 50000],
                ["18T", "UV", 50000, -1],  // Northing out of range
                ["18T", "UV", 50000, 100000],
                ["32X", "AB", 55000, 12345],  // 32X does not exist
            ];

            for (var i = 0; i < tests.size(); i++) {
                var testCoords = tests[i];
                System.println("Test invalid MGRS: " + testCoords.toString());
                var exception = false;
                try {
                    _validateMGRS(testCoords);
                } catch (e) {
                    exception = true;
                }

                if (!exception) {
                    throw new Test.AssertException("Exception was not raised for invalid MGRS!");
                }
            }

            return true;
        }
    }
}
