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
const R = 6378137.0f;
const K0 = 0.9996;

const E = 0.00669438;
const E2 = E * E;
const E3 = E2 * E;
const E_P2 = E / (1.0f - E);

// Precomputed constants
const SQRT_E = Math.sqrt(1.0f - E);
const _E = (1.0f - SQRT_E) / (1.0f + SQRT_E);
const _E2 = _E * _E;
const _E3 = _E2 * _E;
const _E4 = _E3 * _E;
const _E5 = _E4 * _E;

const M1 = (1.0f - E / 4.0f - 3.0f * E2 / 64.0f - 5.0f * E3 / 256.0f);
const M2 = (3.0f * E / 8.0f + 3.0f * E2 / 32.0f + 45.0f * E3 / 1024.0f);
const M3 = (15.0f * E2 / 256.0f + 45.0f * E3 / 1024.0f);
const M4 = (35.0f * E3 / 3072.0f);

const P2 = (3.0f / 2.0f * _E - 27.0f / 32.0f * _E3 + 269.0f / 512.0f * _E5);
const P3 = (21.0f / 16.0f * _E2 - 55.0f / 32.0f * _E4);
const P4 = (151.0f / 96.0f * _E3 - 417.0f / 128.0f * _E5);
const P5 = (1097.0f / 512.0f * _E4);


typedef LatitudeBand as [Number, Float, Float];

const LATITUDE_BANDS = {
    'C' => [1100000, -72.0f, -80.5f],
    'D' => [2000000, -64.0f, -72.0f],
    'E' => [2800000, -56.0f, -64.0f],
    'F' => [3700000, -48.0f, -56.0f],
    'G' => [4600000, -40.0f, -48.0f],
    'H' => [5500000, -32.0f, -40.0f],
    'J' => [6400000, -24.0f, -32.0f],
    'K' => [7300000, -16.0f, -24.0f],
    'L' => [8200000, -8.0f, -16.0f],
    'M' => [9100000, 0.0f, -8.0f],
    'N' => [0, 8.0f, 0.0f],
    'P' => [800000, 16.0f, 8.0f],
    'Q' => [1700000, 24.0f, 16.0f],
    'R' => [2600000, 32.0f, 24.0f],
    'S' => [3500000, 40.0f, 32.0f],
    'T' => [4400000, 48.0f, 40.0f],
    'U' => [5300000, 56.0f, 48.0f],
    'V' => [6200000, 64.0f, 56.0f],
    'W' => [7000000, 72.0f, 64.0f],
    'X' => [7900000, 84.5f, 72.0f],
} as Dictionary<Char, [Number, Float, Float]>;


module NavUtils {

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

        :raise ValueError: If UTM zone is invalid
        */

        // Read first two digits of zone
        var zoneNumber;
        var zoneLetter;
        if (zone.length() == 2) {
            zoneNumber = zone.substring(0, 1).toNumber();
            zoneLetter = zone.substring(1, 2).toCharArray()[0];
        } else {
            zoneNumber = zone.substring(0, 2).toNumber();
            zoneLetter = zone.substring(2, 3).toCharArray()[0];
        }

        if (zoneLetter < 'C' || zoneLetter > 'X' || zoneLetter == 'I' || zoneLetter == 'O' ||  // Valid zone letter range
            zoneNumber == null || zoneNumber < 1 || zoneNumber > 60 || // Valid zone number range
            (zoneLetter == 'X' && (zoneNumber == 32 || zoneNumber == 34 || zoneNumber == 36))) {  // Exceptions
            throw new ValueError(
                "Invalid UTM zone: " + zone.toString());
        }

        if (zoneLetter == 'A' || zoneLetter == 'B' || zoneLetter == 'Y' || zoneLetter == 'Z') {
            // Polar regions need to be handled in UPS (not supported)
            throw new ValueError(
                "Unsupported zone (UPS): " + zone);
        }
    }

    function _validateUTM(utm as UTM) as Void {
        /*
        Validate that UTM coordinates look legit

        :raise ValueError: If UTM coordinates are invalid
        */
        var zone = utm[0];
        var easting = utm[1];
        var northing = utm[2];

        _validateUTMZone(zone);

        if (easting < 100000 || easting >= 1000000 || northing < 0 || northing >= 10000000) {
            throw new ValueError(
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
            P2 * Math.sin(2.0f * mu) +
            P3 * Math.sin(4.0f * mu) +
            P4 * Math.sin(6.0f * mu) +
            P5 * Math.sin(8.0f * mu);

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
            d2 / 2.0f -
            d4 / 24.0f * (5.0f + 3.0f * pTan2 + 10.0f * c - 4.0f * c2 - 9.0f * E_P2) +
            d6 / 720.0f * (61.0f + 90.0f * pTan2 + 298.0f * c + 45.0f * pTan4 - 252.0f * E_P2 - 3.0f * c2));

        var lon = (d -
            d3 / 6.0f * (1.0f + 2.0f * pTan2 + c) +
            d5 / 120.0f * (5.0f - 2.0f * c + 28.0f * pTan2 - 3.0f * c2 + 8.0f * E_P2 + 24.0f * pTan4)) / pCos;

        var zoneLon = (zoneNumber - 1) * Math.PI / 30.0f - Math.PI + Math.PI / 60.0f;

        lon = addRadians(lon, zoneLon);  // [0, 2 * pi) range
        if (lon >= Math.PI) {
            lon -= TWO_PI;
        }

        return [lat * 180.0f / Math.PI, lon * 180.0f / Math.PI];
    }

    function readMGRS(str as String) as MGRS {
        /*
        Parse an MGRS string with a 6-, 8-, or 10-figure grid reference

        Examples of valid formats:
        "12A BC 12345 67890"
        "12ABC1234567890"
        "12ABC 1234567890"

        :raise ValueError: If string format or MGRS coordiantes are invalid
        */
        str = StringUtils.removeTrailingWhitespace(StringUtils.removeLeadingWhitespace(str));

        var zone;
        if (StringUtils.isNumeric(str.substring(1, 2))) {
            var zoneNumber = str.substring(0, 2).toNumber();
            if (zoneNumber == null) {
                throw new ValueError(
                    "Invalid UTM zone: " + str.substring(0, 3));
            }
            var zoneLetter = str.substring(2, 3).toUpper();
            zone = zoneNumber.toString() + zoneLetter; // Converting to number and back removes leading zero if present
            str = str.substring(3, str.length());
        } else {
            zone = str.substring(0, 2).toUpper();
            str = str.substring(2, str.length());
        }

        str = StringUtils.removeLeadingWhitespace(str);

        var gzd = str.substring(0, 2).toUpper();
        str = str.substring(2, str.length());

        str = StringUtils.removeLeadingWhitespace(str);

        var eastingStr;
        var northingStr;
        var precision;  // Precision of grid reference (3, 4, or 5)

        var spaceIndex = str.find(" ");
        if (spaceIndex != null) {
            // Has space separating northing and easting
            if (spaceIndex < 3 || spaceIndex > 5) {
                throw new ValueError(
                    "Invalid easting/northing: " + str);
            }
            eastingStr = str.substring(0, spaceIndex);
            str = str.substring(spaceIndex + 1, str.length());
            precision = spaceIndex;
            if (str.length() != precision) {
                throw new ValueError(
                    "Mismatched easting/northing precision: " + str);
            }
            northingStr = str;
        } else {
            // No space, use length of remaining string
            var len = str.length();
            if (!(len == 6 || len == 8 || len == 10)) {
                throw new ValueError(
                    "Invalid easting/northing: " + str);
            }
            precision = len / 2;
            eastingStr = str.substring(0, precision);
            northingStr = str.substring(precision, len);
        }

        var northing = northingStr.toNumber();
        if (!StringUtils.isNumeric(northingStr) || northing == null) {
            throw new ValueError(
                "Invalid northing: " + northingStr);
        }

        var easting = eastingStr.toNumber();
        if (!StringUtils.isNumeric(eastingStr) || easting == null) {
            throw new ValueError(
                "Invalid easting: " + eastingStr);
        }

        // Adjust for precision
        if (precision == 3) {
            easting *= 100;
            northing *= 100;
        } else if (precision == 4) {
            easting *= 10;
            northing *= 10;
        }

        var result = [zone, gzd, easting, northing];

        _validateMGRS(result);

        return result;
    }

    function dumpMGRS(mgrs as MGRS) as String {
        /*
        Convert MGRS to string with spaces and 1m precision
        
        e.g. "19T UV 12345 67890"
        */
        return mgrs[0] + " " + mgrs[1] + " " + mgrs[2].format("%05d") + " " + mgrs[3].format("%05d");
    }

    function _validateMGRS(mgrs as MGRS) as Void {
        /*
        Validate that MGRS coordinates look legit

        :raise ValueError: If MGRS coordinates are invalid
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
        if (gzdLon < gzdLonMin || gzdLon > gzdLonMax || gzdLat < 'A' || gzdLat > 'V') {
            throw new ValueError(
                "Invalid grid zone designation: " + gzd);
        }

        if (easting < 0 || easting >= 100000 || northing < 0 || northing >= 100000) {
            throw new ValueError(
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

        :raise ValueError: If MGRS coordinates are invalid
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

        var testDistance = 10000.0f;  // 10 km
        var testDirections = [0.0f, Math.PI];  // N, S

        for (var i = 0; i < testDirections.size(); i++) {
            var testDirection = testDirections[i];
            var testLocation = location.getProjectedLocation(testDirection, 10000.0f);
            var testMgrs = testLocation.toGeoString(Position.GEO_MGRS);
            if (testMgrs.substring(0, 5).equals(grid)) {
                // We are still in the same MGRS grid, can do calculation
                var testEasting = testMgrs.substring(5, 10).asNumber();
                var testNorthing = testMgrs.substring(10, 15).asNumber();
                var directionUTM = Math.atan2(testNorthing - northing, testEasting - easting);
                var convergence = testDirection - directionUTM;
                if (convergence > Math.PI) {
                    convergence -= 2.0f * Math.PI;
                }
                return convergence;
            }
        }

        // This should never happen - either of 10km N or 10km S should always be within the same grid
        throw ValueError("");
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
            TestUtils.assertFloatEqual(actual[0], expected[0], {:tol => tolerance});
            TestUtils.assertFloatEqual(actual[1], expected[1], {:tol => tolerance});
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

    (:test)
    function testParseMGRS(logger as Test.Logger) as Boolean {
        // Test parsing of MGRS strings

        // Test expected vs. actual
        var tests = [
            ["50Q KK 07634 66491", ["50Q", "KK", 7634, 66491]],
            ["19TGL0913157968", ["19T", "GL", 9131, 57968]],
            ["19TGL 0913157968", ["19T", "GL", 9131, 57968]],
            ["34H BH 57204 57124", ["34H", "BH", 57204, 57124]],
            ["34H BH 5720 5712", ["34H", "BH", 57200, 57120]],
            ["34H BH 572 571", ["34H", "BH", 57200, 57100]],
            ["50q kk 07634 66491", ["50Q", "KK", 7634, 66491]],  // Lowercase letters okay
            [" 50Q KK 07634 66491", ["50Q", "KK", 7634, 66491]],  // Leading space okay
            ["50Q  KK 07634 66491", ["50Q", "KK", 7634, 66491]],  // Extra spaces okay
            ["50Q KK 07636649  ", ["50Q", "KK", 7630, 66490]],  // Trailing space okay
            ["5Q KB 23840 83053", ["5Q", "KB", 23840, 83053]],  // Single digit UTM zone okay
            ["05Q KB 23840 83053", ["5Q", "KB", 23840, 83053]],  // Single digit UTM zone with leading zero okay
        ];

        for (var i = 0; i < tests.size(); i++) {
            var test = tests[i];
            var testCoords = test[0];
            var expected = test[1];
            System.println("Test MGRS: " + testCoords.toString());
            var actual = readMGRS(testCoords);
            System.println("Expected: " + expected.toString() + ", Actual: " + actual.toString());
            Test.assertEqual(actual.toString(), expected.toString());
        }

        // Test invalid strings throw exceptions
        tests = [
            "50Q KK 7634 66491",  // Mismatched precision
            "50Q K K 07634 66491",  // Misplaced spaces
            "50 Q KK 07634 66491",  // Misplaced spaces
            "50 Q KK 076341 664915",  // Invalid precision
            "50Q KK 07 66",  // Invalid precision
            "50QK 07634 66491",  // Invalid UTM zone / GZD
            "5OQ KK 07634 66491",  // Invalid UTM zone / GZD
            "50Q KK 7634A 66491",  // Invalid grid ref
        ];

        for (var i = 0; i < tests.size(); i++) {
            var testStr = tests[i];
            System.println("Test invalid MGRS: \"" + testStr + "\"");
            var exception = false;
            try {
                readMGRS(testStr);
            } catch (e) {
                exception = true;
            }

            if (!exception) {
                throw new Test.AssertException("Exception was not raised for invalid MGRS string!");
            }
        }
        
        return true;
    }
}
