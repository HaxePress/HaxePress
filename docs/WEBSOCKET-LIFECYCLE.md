# WebSocket session lifecycle

`AbstractWebSocketHandler.getSessions()` returns a snapshot of the active session map. It does not own the socket: each HTTP driver must remove a session and stop its send worker when the underlying connection closes.

The installed Undertow adapter previously removed sessions only from `onCloseMessage`. An RFC 6455 close frame invokes that method, but a TCP reset or a server-side `channel.close()` need not. A reset reproduced the problem with two opened sessions, one close callback and one retained session.

`patches/hxwell-websocket-sessions.patch` adds Undertow's native `addCloseTask` listener and shares an atomic, idempotent detach operation between close frames, transport errors, local closure and failed callbacks. Detaching removes the session and signals its send worker before invoking application callbacks. A callback exception cannot prevent removal or the close handshake. `getSessions()` now iterates a synchronized map copy so concurrent removal cannot invalidate an iterator.

Crossbyte already handles normal transport closure. Its registry removal previously waited behind queued application callbacks. `patches/hxwell-crossbyte-sessions.patch` detaches on the actual transport close even when an earlier message callback is waiting. The `onClose` callback keeps its existing serialized delivery. The same patch exposes the driver's existing message/queue/output size settings through its builder, allowing the MCP image tool's bounded responses to fit.

Both patches apply to project-local dependencies through `scripts/setup.py`. Sibling framework and driver checkouts remain untouched.

Run the Crossbyte regression after building the integration application and its packages:

```sh
python3 tests/run.py --only websocket_lifecycle
```

Run the independent Undertow regression with a JDK and Maven installed:

```sh
python3 tests/undertow_lifecycle.py
```

The Undertow harness uses the real HxWell WebSocket callback and Undertow 2.3.27.Final; a minimal native HTTP handler exposes test counters. It does not exercise HxWell's unrelated Undertow HTTP request parser. Its Maven dependencies stay under `.tools` and do not enter the production Crossbyte runtime.

The shared tests cover normal close frames, TCP resets, server-initiated closure, message/close callback failures and 20 reconnects. After the fix, Undertow reports **25 opened / 25 closed / 0 registered**. Crossbyte additionally verifies immediate detachment while a message callback is blocked. These checks address observed closure; a network partition that produces no transport event still depends on the driver's heartbeat/timeout policy.
