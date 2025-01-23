import Toybox.Lang;


module NavUtils {

    // Replacement for InvalidValueException that is easier to handle
    class ValueError extends Lang.InvalidValueException {
        
        private var _msg as String;

        function initialize(msg as String) {
            _msg = msg;
            Lang.InvalidValueException.initialize(toString());
        }

        function toString() {
            return "ValueError: " + _msg;
        }
    }
}
