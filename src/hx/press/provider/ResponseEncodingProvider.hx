package hx.press.provider;

import hx.press.ResponseBodies;
import hx.well.http.Response;
import hx.well.provider.AbstractProvider;

/** Sends text responses from pooled UTF-8 buffers instead of a fresh copy per response. */
class ResponseEncodingProvider extends AbstractProvider {
    public function boot():Void {
        Response.textEncoder = ResponseBodies.encode;
    }
}
