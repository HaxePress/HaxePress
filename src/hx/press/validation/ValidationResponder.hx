package hx.press.validation;

import hx.well.http.AbstractResponse;
import hx.well.http.Request;

/** Response contract for the framework's native validation failure (HTTP 422). */
interface ValidationResponder {
    public function validationFailed(request:Request):AbstractResponse;
}
