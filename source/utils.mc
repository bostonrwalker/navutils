import Toybox.Lang;
using Toybox.Math;
using Toybox.Test;


/*******************************************************************************
Internal utility functions
********************************************************************************
Created: 11 Jan 2025 by Boston W
*******************************************************************************/


const TWO_PI = 2.0f * Math.PI as Float;


module NavUtils {

    class Utils {

        static function getDefault(dict as Dictionary, key as Object, defaultValue as Object?) as Object? {
            /*
            Get a value from a dictionary, returning a default value if the key does not exist
            */
            return dict.hasKey(key) ? dict[key] : defaultValue;
        }

    }

    class StringUtils {

        static function removeLeadingWhitespace(str as String) {
            var chars = str.toCharArray();
            var numLeadingWhitespace = 0;
            for (var i = 0; i < chars.size(); i++) {
                var char = chars[i];
                if (char == ' ' || char == '\t') {
                    numLeadingWhitespace = i + 1;
                } else {
                    break;
                }
            }
            return str.substring(numLeadingWhitespace, str.length());
        }

        static function removeTrailingWhitespace(str as String) {
            var lastNonWhitespace = -1;
            var chars = str.toCharArray();
            for (var i = chars.size() - 1; i >= 0; i--) {
                var char = chars[i];
                if (!(char == ' ' || char == '\t')) {
                    lastNonWhitespace = i;
                    break;
                }
            }
            return str.substring(0, lastNonWhitespace + 1);
        }

        static function isNumeric(string as String) as Boolean {
            // Test if string is alphanumeric
            var chars = string.toCharArray();
            for (var i = 0; i < chars.size(); i++) {
                var char = chars[i];
                if (!(char >= '0' && char <= '9')) {
                    return false;
                }
            }
            return true;
        }

        static function split(str as String, token as String) as Array<String> {
            // Split a string into an array of strings based on a token
            var result = [];
            while (true) {
                var occurrence = str.find(token);
                if (occurrence != null) {
                    result.add(str.substring(0, occurrence));
                    str = str.substring(occurrence + 1, str.length());
                } else {
                    result.add(str);
                    break;
                }
            }
            return result;
        }
    }


    class TestUtils {

        static function assertFloatEqual(actual as Float?, expected as Float?, options as {:tol as Float}) as Void {
            var tol = Utils.getDefault(options, :tol, 1e-6) as Float;
            if (expected != null && actual != null) {
                var diff = (actual - expected).abs();
                if (diff > tol) {
                    throw new Test.AssertException("ASSERTION FAILED -- expected: " + expected.toString() + ", actual: " + actual.toString());
                }
            } else if (expected == null && actual != null) {
                throw new Test.AssertException("ASSERTION FAILED -- expected: null, actual: " + actual.toString());
            } else if (expected != null && actual == null) {
                throw new Test.AssertException("ASSERTION FAILED -- expected: " + expected.toString() + ", actual: null");
            }
        }
    }
}
