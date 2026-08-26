-- Root package for RFC 6455 WebSocket client library
package Websocket is
   pragma Pure;
   
   -- This package provides WebSocket protocol implementation according to RFC 6455.
   -- The library is structured into:
   --   - Websocket.Frames: frame codec (encoding/decoding)
   --   - (future) Websocket.Connection: TCP connection handling
   --   - (future) Websocket.Handshake: HTTP upgrade handshake
   
end Websocket;
