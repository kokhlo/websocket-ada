-- Test runner for Websocket.Handshake + Base64
-- Plain Ada test suite: prints PASS/FAIL, exits nonzero on failure
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Command_Line;
with Ada.Streams; use Ada.Streams;
with Websocket.Base64; use Websocket.Base64;
with Websocket.Handshake; use Websocket.Handshake;

procedure Test_Handshake is

   Test_Count : Natural := 0;
   Fail_Count : Natural := 0;

   procedure Assert (Condition : Boolean; Message : String) is
   begin
      Test_Count := Test_Count + 1;
      if Condition then
         Put_Line ("  PASS: " & Message);
      else
         Put_Line ("  FAIL: " & Message);
         Fail_Count := Fail_Count + 1;
      end if;
   end Assert;

   function Index (S : String; Pattern : String) return Natural is
   begin
      for I in S'First .. S'Last - Pattern'Length + 1 loop
         if S (I .. I + Pattern'Length - 1) = Pattern then
            return I;
         end if;
      end loop;
      return 0;
   end Index;

   procedure Run_Tests;

   -------------------------------------------------------------------
   -- Test suite
   -------------------------------------------------------------------
   procedure Run_Tests is

      -- Base64 tests first (small self-contained layer)
      procedure Test_Base64 is
         -- RFC 4648 test vectors
         Enc1 : constant String := Encode (Stream_Element_Array'(1 => Character'Pos ('f')));
         Enc2 : constant String := Encode (Stream_Element_Array'(Character'Pos ('f'),
                                                                  Character'Pos ('o')));
         Enc3 : constant String := Encode (Stream_Element_Array'(Character'Pos ('f'),
                                                                  Character'Pos ('o'),
                                                                  Character'Pos ('o')));
         Enc4 : constant String := Encode (Stream_Element_Array'(Character'Pos ('f'),
                                                                  Character'Pos ('o'),
                                                                  Character'Pos ('o'),
                                                                  Character'Pos ('b')));

         Dec1 : constant Stream_Element_Array := Decode ("Zg==");
         Dec2 : constant Stream_Element_Array := Decode ("Zm8=");
         Dec3 : constant Stream_Element_Array := Decode ("Zm9v");
      begin
         Put_Line ("=== Base64 Tests ===");
         Assert (Enc1 = "Zg==", "encode 'f'");
         Assert (Enc2 = "Zm8=", "encode 'fo'");
         Assert (Enc3 = "Zm9v", "encode 'foo'");
         Assert (Enc4 = "Zm9vYg==", "encode 'foob'");

         Assert (Dec1'Length = 1 and then Dec1 (Dec1'First) = Character'Pos ('f'),
                 "decode 'Zg=='");
         Assert (Dec2'Length = 2 and then Dec2 (Dec2'First) = Character'Pos ('f')
                 and then Dec2 (Dec2'First + 1) = Character'Pos ('o'),
                 "decode 'Zm8='");
         Assert (Dec3'Length = 3, "decode 'Zm9v' length");

         -- Invalid base64
         Assert (Decode ("Z")'Length = 0, "reject odd-length");
         Assert (Decode ("====Invalid=")'Length = 0, "reject malformed");
         New_Line;
      end Test_Base64;

      procedure Test_Handshake is
         -- RFC 6455 §1.3 official test vector:
         -- key "dGhlIHNhbXBsZSBub25jZQ==" → accept "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
         Key         : constant String := "dGhlIHNhbXBsZSBub25jZQ==";
         Accept_Str  : constant String := Compute_Accept (Key);
         Request     : constant String := Build_Client_Request
            (Host => "example.com", Port => 80, Path => "/", Random_Key => Key);

         -- A minimal valid 101 response
         Response_Valid : constant String :=
            "HTTP/1.1 101 Switching Protocols" & ASCII.CR & ASCII.LF &
            "Upgrade: websocket" & ASCII.CR & ASCII.LF &
            "Connection: Upgrade" & ASCII.CR & ASCII.LF &
            "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" & ASCII.CR & ASCII.LF &
            ASCII.CR & ASCII.LF;

         -- Case-insensitive headers (server lowercased "websocket")
         Response_Lowercased : constant String :=
            "HTTP/1.1 101 Switching Protocols" & ASCII.CR & ASCII.LF &
            "upgrade: websocket" & ASCII.CR & ASCII.LF &
            "connection: upgrade" & ASCII.CR & ASCII.LF &
            "sec-websocket-accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" & ASCII.CR & ASCII.LF &
            ASCII.CR & ASCII.LF;

         -- Connection header as comma-separated list (RFC 7230 §6.1)
         Response_Connection_List : constant String :=
            "HTTP/1.1 101 Switching Protocols" & ASCII.CR & ASCII.LF &
            "Upgrade: websocket" & ASCII.CR & ASCII.LF &
            "Connection: keep-alive, Upgrade" & ASCII.CR & ASCII.LF &
            "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" & ASCII.CR & ASCII.LF &
            ASCII.CR & ASCII.LF;

         -- 400 Bad Request
         Response_400 : constant String :=
            "HTTP/1.1 400 Bad Request" & ASCII.CR & ASCII.LF &
            "Content-Length: 0" & ASCII.CR & ASCII.LF &
            ASCII.CR & ASCII.LF;

         Result : Status;
      begin
         Put_Line ("=== Handshake Tests ===");

         -- RFC test vector
         Assert (Accept_Str = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", "RFC 6455 test vector");

         -- Request construction
         Assert (Request'Length > 0, "Build_Client_Request returned nonempty");
         -- The spec mandates GET, Host, Upgrade, Connection, Sec-WebSocket-Key,
         -- Sec-WebSocket-Version. Quick smoke test:
         declare
            Req : constant String := Request;
         begin
            Assert (Req (Req'First .. Req'First + 3) = "GET ", "request starts GET");
            Assert (Index (Req, "Host: example.com") > 0, "request has Host header");
            Assert (Index (Req, "Upgrade: websocket") > 0, "request has Upgrade header");
            Assert (Index (Req, "Sec-WebSocket-Key: " & Key) > 0,
                    "request has Sec-WebSocket-Key");
         end;

         -- Validate: happy path
         Result := Validate_Server_Response (Response_Valid, Accept_Str);
         Assert (Result.Kind = OK, "valid 101 response accepted");

         -- Validate: case-insensitive headers
         Result := Validate_Server_Response (Response_Lowercased, Accept_Str);
         Assert (Result.Kind = OK, "lowercased header values accepted");

         -- Validate: Connection header with comma-separated tokens
         Result := Validate_Server_Response (Response_Connection_List, Accept_Str);
         Assert (Result.Kind = OK, "Connection: keep-alive, Upgrade accepted");

         -- Validate: 400 Bad Request → Wrong_Status
         Result := Validate_Server_Response (Response_400, Accept_Str);
         Assert (Result.Kind = Wrong_Status, "400 Bad Request rejected");
         Assert (Result.Code = 400, "Code = 400");

         -- Validate: missing Sec-WebSocket-Accept → Accept_Mismatch
         declare
            Missing_Accept : constant String :=
               "HTTP/1.1 101 Switching Protocols" & ASCII.CR & ASCII.LF &
               "Upgrade: websocket" & ASCII.CR & ASCII.LF &
               "Connection: Upgrade" & ASCII.CR & ASCII.LF &
               ASCII.CR & ASCII.LF;
         begin
            Result := Validate_Server_Response (Missing_Accept, Accept_Str);
            Assert (Result.Kind = Accept_Mismatch, "missing Accept → Accept_Mismatch");
         end;

         -- Validate: wrong Sec-WebSocket-Accept value
         declare
            Wrong_Accept : constant String :=
               "HTTP/1.1 101 Switching Protocols" & ASCII.CR & ASCII.LF &
               "Upgrade: websocket" & ASCII.CR & ASCII.LF &
               "Connection: Upgrade" & ASCII.CR & ASCII.LF &
               "Sec-WebSocket-Accept: wrongvalue" & ASCII.CR & ASCII.LF &
               ASCII.CR & ASCII.LF;
         begin
            Result := Validate_Server_Response (Wrong_Accept, Accept_Str);
            Assert (Result.Kind = Accept_Mismatch, "wrong Accept → Accept_Mismatch");
         end;

         New_Line;
      end Test_Handshake;

   begin
      Put_Line ("RFC 6455 WebSocket Handshake + Base64 Tests");
      Put_Line ("============================================");
      New_Line;

      Test_Base64;
      Test_Handshake;

   end Run_Tests;

begin
   Run_Tests;

   Put_Line ("============================================");
   Put_Line ("Tests run:" & Test_Count'Image);
   Put_Line ("Failures: " & Fail_Count'Image);

   if Fail_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Put_Line ("All tests PASSED.");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
   end if;
end Test_Handshake;
