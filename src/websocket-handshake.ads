-- RFC 6455 opening handshake: HTTP Upgrade request construction and
-- server response validation (§4.1 client requirements, §4.2.2 client checks).
--
-- Pure text layer, no sockets: build a request String, hand it to a
-- transport, feed the response String back in. This keeps the layer
-- unit-testable before the TCP connection code exists.
--
-- Typical flow (client side):
--   Key     := Websocket.Handshake.Generate_Key;      -- 16 random bytes, base64
--   Request := Websocket.Handshake.Build_Client_Request (Host, Port, Path, Key);
--   ... send Request, read the server's response bytes as a String ...
--   Result := Websocket.Handshake.Validate_Server_Response
--                (Response, Websocket.Handshake.Compute_Accept (Key));

package Websocket.Handshake is

   -- The GUID every Sec-WebSocket-Accept is built from
   -- (RFC 6455 §4.2.2, Sec-WebSocket-Accept definition)
   WS_Magic_String : constant String := "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

   -- Headers this client requires in a 101 response (RFC 6455 §4.2.2)
   type Required_Header is (Upgrade_Header, Connection_Header, Accept_Header);

   -- Why a server response was accepted or rejected
   type Status_Kind is
      (OK,               -- handshake complete, connection is upgraded
       Wrong_Status,     -- server did not answer 101 Switching Protocols
       Missing_Header,   -- a required header absent or empty
       Accept_Mismatch); -- Sec-WebSocket-Accept has the wrong value

   type Status is record
      Kind     : Status_Kind := OK;
      Code     : Natural := 0;          -- set for Wrong_Status: HTTP code sent
      Header   : Required_Header := Upgrade_Header;  -- set for Missing_Header
   end record;

   -- Build the full client GET request as a String (RFC 6455 §4.1).
   -- Random_Key is the already-base64-encoded 16 random bytes
   -- (see Generate_Key). Deterministic given the inputs.
   function Build_Client_Request
      (Host : String;
       Port : Natural;
       Path : String;
       Random_Key : String)
      return String;

   -- Sec-WebSocket-Accept = base64(SHA1(key || magic)) (RFC 6455 §4.2.2)
   function Compute_Accept (Key : String) return String;

   -- Check a server response against RFC 6455 §4.2.2 client requirements:
   -- status 101, Upgrade: websocket, Connection containing Upgrade,
   -- Sec-WebSocket-Accept equal to Expected_Accept.
   function Validate_Server_Response
      (Response : String;
       Expected_Accept : String)
      return Status;

   -- 16 random bytes, base64-encoded: the Sec-WebSocket-Key value
   function Generate_Key return String;

end Websocket.Handshake;
