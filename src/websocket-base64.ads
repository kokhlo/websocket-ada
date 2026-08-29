-- Base64 encoding/decoding (RFC 4648) for the WebSocket handshake layer
-- RFC 6455 §4.2.2 requires base64 of the 16-byte Sec-WebSocket-Key and of the
-- SHA-1 digest used for Sec-WebSocket-Accept. GNAT's runtime provides SHA-1
-- (GNAT.SHA1) but no base64, so this is a small self-contained implementation.

with Ada.Streams; use Ada.Streams;

package Websocket.Base64 is

   -- Encode binary data as a base64 string (RFC 4648 §4, with padding '=')
   function Encode (Data : Stream_Element_Array) return String;

   -- Decode a base64 string back to bytes.
   -- Padding is optional at the end; whitespace is not allowed.
   -- Returns False (and no data) if the input is not valid base64.
   function Try_Decode
      (Item    : String;
       Result  : out Stream_Element_Array;
       Last    : out Stream_Element_Offset)
       return Boolean;

   -- Convenience: decode into a freshly sized array (empty on failure)
   function Decode (Item : String) return Stream_Element_Array;

end Websocket.Base64;
