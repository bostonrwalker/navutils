import Toybox.Lang;
using Toybox.Math;
using Toybox.Test;


/*******************************************************************************
Internal utility functions
********************************************************************************
Created: 11 Jan 2025 by Boston W
*******************************************************************************/


const TWO_PI = 2 * Math.PI as Float;


function getDefault(dict as Dictionary, key as Object, defaultValue as Object?) as Object? {
    /*
    Get a value from a dictionary, returning a default value if the key does not exist
    */
    return dict.hasKey(key) ? dict[key] : defaultValue;
}

function assertFloatEqual(actual as Float?, expected as Float?, options as {:tol as Float}) as Void {
    var tol = getDefault(options, :tol, 1e-6) as Float;
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

