import Toybox.Lang;
using Toybox.Math;

/*******************************************************************************
Constants
********************************************************************************
Created: 4 Feb 2025 by Boston W
*******************************************************************************/

const HALF_PI = 0.5f * Math.PI as Float;
const TWO_PI = 2.0f * Math.PI as Float;

/*
WGS84 model
*/

// Spheroid parameters
const R = 6378137.0f; // Radius of Earth in meters
const K0 = 0.9996f;
const E = 0.00669438f;

// Cardinal directions for radsToCardinalDir() function
const CARDINAL_DIRS_PRECISION_1 = ["N", "E", "S", "W"];
const CARDINAL_DIRS_PRECISION_2 = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
const CARDINAL_DIRS_PRECISION_3 = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"];
