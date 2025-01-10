import Toybox.Lang;
using Toybox.Math;
using Toybox.Test;
using Toybox.System;


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
} as Dictionary<Char, LatitudeBand>;


module NavUtils {

    function _validateMGRS(mgrs as MGRS) as Void {
        /*
        Validate that MGRS coordinates look legit

        :raise InvalidValueException: If MGRS coordinates are invalid
        */
        var zone = mgrs[0];
        var gzd = mgrs[1];
        // var easting = mgrs[2];
        // var northing = mgrs[3];

        var zoneNumber = zone.substring(0, 2).toNumber();
        var zoneLetter = zone.substring(2, 3).toCharArray()[0];

        if (zoneLetter == 'A' || zoneLetter == 'B' || zoneLetter == 'Y' || zoneLetter == 'Z') {
            // Polar regions need to be handled in UPS (not supported)
            throw new InvalidValueException(
                "Unsupported UTM zone: " + zone);
        }

        if (zoneLetter == 'X' && (zoneNumber == 32 || zoneNumber == 34 || zoneNumber == 36)) {
            // These regions don't exist
            throw new InvalidValueException(
                "Invalid UTM zone: " + zone);
        }

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

        // A-M: South hemisphere, N-Z: North hemisphere
        var hemisphere = zone.toCharArray()[2] < 'N' ? SOUTH : NORTH;

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

        return [hemisphere, zone, utmEasting, utmNorthing];
    }


    (:test)
    function testMGRSToUTM(logger as Test.Logger) as Boolean {
        // Test conversion of MGRS to UTM

        // Test expected vs. actual
        var tests = [
            [["50Q", "KK", 7634, 66491], [NORTH, "50Q", 207634, 2466491]],
            [["19T", "GL", 9131, 57968], [NORTH, "19T", 709131, 5057968]],
            [["34H", "BH", 57204, 57124], [SOUTH, "34H", 257204, 6257124]],
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
    function testValidateMGRS(logger as Test.Logger) as Boolean {
        // Test some invalid MGRS coordinates and ensure that an exception is thrown
        var tests = [
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
