-- Test runner for Websocket.Frames
-- Plain Ada test suite: prints PASS/FAIL, exits nonzero on failure
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Command_Line;
with Ada.Streams; use Ada.Streams;
with Websocket.Frames; use Websocket.Frames;
with Websocket.Utf8;

procedure Test_Runner is

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

   procedure Run_Tests;

   -------------------------------------------------------------------
   -- Test suite
   -------------------------------------------------------------------
   procedure Run_Tests is
      F, F_Decoded : Frame;
      Buffer : Payload_Data;
      Status : Decode_Status;
      Consumed : Stream_Element_Count;
   begin
      Put_Line ("RFC 6455 WebSocket Frame Codec Tests");
      Put_Line ("=====================================");
      New_Line;

      -----------------------------------------------------------
      -- Test 1: Text frame roundtrip (client-masked)
      -----------------------------------------------------------
      Put_Line ("Test 1: Text frame roundtrip (client-masked)");
      F := (FIN => True,
            RSV1 => False, RSV2 => False, RSV3 => False,
            Opcode => Text,
            Masked => True,
            Payload_Length => 5,
            Masking_Key => (16#12#, 16#34#, 16#56#, 16#78#),
            Payload => <>);
      F.Payload.Append (Character'Pos ('H'));
      F.Payload.Append (Character'Pos ('e'));
      F.Payload.Append (Character'Pos ('l'));
      F.Payload.Append (Character'Pos ('l'));
      F.Payload.Append (Character'Pos ('o'));
      
      Encode (F, Buffer);
      Decode (Buffer, F_Decoded, Consumed, Status);
      
      Assert (Status = Success, "decode status success");
      Assert (Consumed = Stream_Element_Count (Buffer.Length), "consumed all bytes");
      Assert (F_Decoded.FIN = True, "FIN preserved");
      Assert (F_Decoded.Opcode = Text, "opcode preserved");
      Assert (Natural (F_Decoded.Payload.Length) = 5, "payload length preserved");
      Assert (F_Decoded.Payload.Element (0) = Character'Pos ('H'), "payload[0] == 'H'");
      Assert (F_Decoded.Payload.Element (4) = Character'Pos ('o'), "payload[4] == 'o'");
      New_Line;

      -----------------------------------------------------------
      -- Test 2: Binary frame with 200-byte payload (16-bit length)
      -----------------------------------------------------------
      Put_Line ("Test 2: Binary frame 200-byte payload (16-bit extended length)");
      F := (FIN => True,
            RSV1 => False, RSV2 => False, RSV3 => False,
            Opcode => Binary,
            Masked => True,
            Payload_Length => 200,
            Masking_Key => (16#AA#, 16#BB#, 16#CC#, 16#DD#),
            Payload => <>);
      for I in 0 .. 199 loop
         F.Payload.Append (Stream_Element (I mod 256));
      end loop;
      
      Encode (F, Buffer);
      Assert (Buffer.Element (1) = (16#80# or 126), "byte1 has MASK+126 marker");
      Assert (Buffer.Element (2) = 0, "extended length MSB == 0");
      Assert (Buffer.Element (3) = 200, "extended length LSB == 200");
      
      Decode (Buffer, F_Decoded, Consumed, Status);
      Assert (Status = Success, "decode status success");
      Assert (Natural (F_Decoded.Payload.Length) = 200, "payload length == 200");
      Assert (F_Decoded.Payload.Element (0) = 0, "payload[0] == 0");
      Assert (F_Decoded.Payload.Element (199) = 199, "payload[199] == 199");
      New_Line;

      -----------------------------------------------------------
      -- Test 3: Server unmasked Close frame roundtrip
      -----------------------------------------------------------
      Put_Line ("Test 3: Server unmasked Close frame");
      F := (FIN => True,
            RSV1 => False, RSV2 => False, RSV3 => False,
            Opcode => Close,
            Masked => False,
            Payload_Length => 2,
            Masking_Key => (others => 0),
            Payload => <>);
      F.Payload.Append (16#03#);  -- Status code MSB
      F.Payload.Append (16#E8#);  -- Status code LSB (1000 = normal closure)
      
      Encode (F, Buffer);
      Assert ((Buffer.Element (1) and 16#80#) = 0, "byte1 MASK bit clear");
      
      Decode (Buffer, F_Decoded, Consumed, Status);
      Assert (Status = Success, "decode status success");
      Assert (F_Decoded.Opcode = Close, "opcode == Close");
      Assert (F_Decoded.Masked = False, "unmasked");
      Assert (Natural (F_Decoded.Payload.Length) = 2, "payload length == 2");
      New_Line;

      -----------------------------------------------------------
      -- Test 4: Ping/Pong frames
      -----------------------------------------------------------
      Put_Line ("Test 4: Ping frame");
      F := (FIN => True,
            RSV1 => False, RSV2 => False, RSV3 => False,
            Opcode => Ping,
            Masked => False,
            Payload_Length => 4,
            Masking_Key => (others => 0),
            Payload => <>);
      F.Payload.Append (Character'Pos ('p'));
      F.Payload.Append (Character'Pos ('i'));
      F.Payload.Append (Character'Pos ('n'));
      F.Payload.Append (Character'Pos ('g'));
      
      Encode (F, Buffer);
      Decode (Buffer, F_Decoded, Consumed, Status);
      Assert (Status = Success, "decode status success");
      Assert (F_Decoded.Opcode = Ping, "opcode == Ping");
      New_Line;

      Put_Line ("Test 5: Pong frame");
      F.Opcode := Pong;
      Encode (F, Buffer);
      Decode (Buffer, F_Decoded, Consumed, Status);
      Assert (Status = Success, "decode status success");
      Assert (F_Decoded.Opcode = Pong, "opcode == Pong");
      New_Line;

      -----------------------------------------------------------
      -- Test 6: Partial buffer → Need_More_Data
      -----------------------------------------------------------
      Put_Line ("Test 6: Incremental decode (Need_More_Data → Success)");
      F := (FIN => True,
            RSV1 => False, RSV2 => False, RSV3 => False,
            Opcode => Text,
            Masked => False,
            Payload_Length => 10,
            Masking_Key => (others => 0),
            Payload => <>);
      for I in 0 .. 9 loop
         F.Payload.Append (Character'Pos ('A') + Stream_Element (I));
      end loop;
      
      Encode (F, Buffer);
      
      -- Feed partial buffer (only first 5 bytes)
      declare
         Partial : Payload_Data;
      begin
         for I in 0 .. 4 loop
            Partial.Append (Buffer.Element (I));
         end loop;
         Decode (Partial, F_Decoded, Consumed, Status);
         Assert (Status = Need_More_Data, "partial decode returns Need_More_Data");
      end;
      
      -- Feed complete buffer
      Decode (Buffer, F_Decoded, Consumed, Status);
      Assert (Status = Success, "complete decode returns Success");
      Assert (Natural (F_Decoded.Payload.Length) = 10, "payload length == 10");
      New_Line;

      -----------------------------------------------------------
      -- Test 7: Control frame >125 bytes → Protocol_Error
      -----------------------------------------------------------
      Put_Line ("Test 7: Control frame >125 bytes → Protocol_Error");
      F := (FIN => True,
            RSV1 => False, RSV2 => False, RSV3 => False,
            Opcode => Ping,
            Masked => False,
            Payload_Length => 126,
            Masking_Key => (others => 0),
            Payload => <>);
      for I in 0 .. 125 loop
         F.Payload.Append (0);
      end loop;
      
      Encode (F, Buffer);
      Decode (Buffer, F_Decoded, Consumed, Status);
      Assert (Status = Protocol_Error, "decode returns Protocol_Error");
      New_Line;

      -----------------------------------------------------------
      -- Test 8: Masking correctness (XOR idempotent)
      -----------------------------------------------------------
      Put_Line ("Test 8: Masking correctness (double-apply = identity)");
      declare
         Original : Payload_Data;
         Key : constant Masking_Key_Type := (16#11#, 16#22#, 16#33#, 16#44#);
      begin
         Original.Append (Character'Pos ('T'));
         Original.Append (Character'Pos ('e'));
         Original.Append (Character'Pos ('s'));
         Original.Append (Character'Pos ('t'));
         
         declare
            Working : Payload_Data := Original;
         begin
            Apply_Mask (Working, Key);
            Assert (Working.Element (0) /= Original.Element (0), "masked differs from original");
            
            Apply_Mask (Working, Key);
            Assert (Working.Element (0) = Original.Element (0), "double-mask == identity (byte 0)");
            Assert (Working.Element (3) = Original.Element (3), "double-mask == identity (byte 3)");
         end;
      end;
      New_Line;

      -----------------------------------------------------------
      -- Test 9: RFC validation rules on decode
      -- (RSV bits, reserved opcodes, fragmented control frames,
      --  close payload shapes, oversized 64-bit length)
      -----------------------------------------------------------
      Put_Line ("Test 9: RSV bit set is a protocol error");
      declare
         Raw : Payload_Data;
      begin
         -- FIN=1, RSV1=1, opcode=Text, unmasked, len=0
         Raw.Append (16#C1#);
         Raw.Append (16#00#);
         Decode (Raw, F_Decoded, Consumed, Status);
         Assert (Status = Protocol_Error, "RSV1 set rejected");
         Assert (Consumed = 0, "no bytes consumed on error");

         Raw.Clear;
         Raw.Append (16#A1#);            -- FIN=1, RSV2=1
         Raw.Append (16#00#);
         Decode (Raw, F_Decoded, Consumed, Status);
         Assert (Status = Protocol_Error, "RSV2 set rejected");

         Raw.Clear;
         Raw.Append (16#91#);            -- FIN=1, RSV3=1
         Raw.Append (16#00#);
         Decode (Raw, F_Decoded, Consumed, Status);
         Assert (Status = Protocol_Error, "RSV3 set rejected");
      end;
      New_Line;

      Put_Line ("Test 10: reserved opcodes are protocol errors");
      declare
         Raw : Payload_Data;
      begin
         for Op in 3 .. 7 loop
            Raw.Clear;
            Raw.Append (16#80# or Stream_Element (Op));
            Raw.Append (16#00#);
            Decode (Raw, F_Decoded, Consumed, Status);
            Assert (Status = Protocol_Error,
                    "non-control reserved opcode" & Integer'Image (Op)
                    & " rejected");
         end loop;
         for Op in 16#B# .. 16#F# loop
            Raw.Clear;
            Raw.Append (16#80# or Stream_Element (Op));
            Raw.Append (16#00#);
            Decode (Raw, F_Decoded, Consumed, Status);
            Assert (Status = Protocol_Error,
                    "control reserved opcode 0x" & Integer'Image (Op)
                    & " rejected");
         end loop;
      end;
      New_Line;

      Put_Line ("Test 11: fragmented control frame is a protocol error");
      declare
         Raw : Payload_Data;
      begin
         -- FIN=0, opcode=Ping, unmasked, len=0
         Raw.Append (16#09#);
         Raw.Append (16#00#);
         Decode (Raw, F_Decoded, Consumed, Status);
         Assert (Status = Protocol_Error, "FIN=0 Ping rejected");
      end;
      New_Line;

      Put_Line ("Test 12: 64-bit length over Stream_Element_Count rejected");
      declare
         Raw : Payload_Data;
      begin
         -- FIN=1, opcode=Binary, unmasked, 64-bit length = 16#FF...FF#
         Raw.Append (16#82#);
         Raw.Append (16#7F#);
         for I in 1 .. 8 loop
            Raw.Append (16#FF#);
         end loop;
         Decode (Raw, F_Decoded, Consumed, Status);
         Assert (Status = Protocol_Error,
                 "length 2**64-1 rejected without crash");
      end;
      New_Line;

      Put_Line ("Test 13: Decode_Client close-payload validation");
      declare
         Raw : Payload_Data;
      begin
         -- masked server frame: FIN=1, opcode=Text, MASK=1, len=1
         Raw.Clear;
         Raw.Append (16#81#);
         Raw.Append (16#81#);
         Raw.Append (16#00#); Raw.Append (16#00#);
         Raw.Append (16#00#); Raw.Append (16#00#);
         Raw.Append (16#41#);
         Decode_Client (Raw, F_Decoded, Consumed, Status);
         Assert (Status = Protocol_Error, "masked server frame rejected");

         -- Close, payload = 1 byte (truncated code)
         Raw.Clear;
         Raw.Append (16#88#);
         Raw.Append (16#01#);
         Raw.Append (16#03#);
         Decode_Client (Raw, F_Decoded, Consumed, Status);
         Assert (Status = Protocol_Error, "1-byte close payload rejected");

         -- Close, code 1005 (reserved, must not appear on the wire)
         Raw.Clear;
         Raw.Append (16#88#);
         Raw.Append (16#02#);
         Raw.Append (16#03#); Raw.Append (16#ED#);
         Decode_Client (Raw, F_Decoded, Consumed, Status);
         Assert (Status = Protocol_Error, "close code 1005 rejected");

         -- Close, code 0 (invalid)
         Raw.Clear;
         Raw.Append (16#88#);
         Raw.Append (16#02#);
         Raw.Append (16#00#); Raw.Append (16#00#);
         Decode_Client (Raw, F_Decoded, Consumed, Status);
         Assert (Status = Protocol_Error, "close code 0 rejected");

         -- Close, code 1000 + invalid UTF-8 reason (0xFF lead)
         Raw.Clear;
         Raw.Append (16#88#);
         Raw.Append (16#03#);
         Raw.Append (16#03#); Raw.Append (16#E8#); Raw.Append (16#FF#);
         Decode_Client (Raw, F_Decoded, Consumed, Status);
         Assert (Status = Protocol_Error, "invalid UTF-8 close reason rejected");

         -- Close, code 1000 + valid 2-byte UTF-8 reason (U+00E9 é)
         Raw.Clear;
         Raw.Append (16#88#);
         Raw.Append (16#04#);
         Raw.Append (16#03#); Raw.Append (16#E8#);
         Raw.Append (16#C3#); Raw.Append (16#A9#);
         Decode_Client (Raw, F_Decoded, Consumed, Status);
         Assert (Status = Success, "code 1000 + valid UTF-8 reason accepted");

         -- Close, code 1000, no reason
         Raw.Clear;
         Raw.Append (16#88#);
         Raw.Append (16#02#);
         Raw.Append (16#03#); Raw.Append (16#E8#);
         Decode_Client (Raw, F_Decoded, Consumed, Status);
         Assert (Status = Success, "bare code 1000 accepted");

         -- Close, code 3000 (registered range), no reason
         Raw.Clear;
         Raw.Append (16#88#);
         Raw.Append (16#02#);
         Raw.Append (16#0B#); Raw.Append (16#B8#);
         Decode_Client (Raw, F_Decoded, Consumed, Status);
         Assert (Status = Success, "close code 3000 accepted");

         -- Close, empty payload
         Raw.Clear;
         Raw.Append (16#88#);
         Raw.Append (16#00#);
         Decode_Client (Raw, F_Decoded, Consumed, Status);
         Assert (Status = Success, "empty close payload accepted");

         -- Unmasked text frame from server: fine
         Raw.Clear;
         Raw.Append (16#81#);
         Raw.Append (16#01#);
         Raw.Append (16#41#);
         Decode_Client (Raw, F_Decoded, Consumed, Status);
         Assert (Status = Success, "unmasked server text frame accepted");
      end;
      New_Line;

      Put_Line ("Test 14: UTF-8 validator unit checks");
      declare
         V    : Websocket.Utf8.Validator;
         Bad  : constant Stream_Element_Array (1 .. 1) := (1 => 16#FF#);
         Good : constant Stream_Element_Array (1 .. 1) := (1 => 16#41#);
         Trunc : constant Stream_Element_Array (1 .. 1) := (1 => 16#C2#);
      begin
         Websocket.Utf8.Reset (V);
         Assert (not Websocket.Utf8.Is_Valid (Bad), "0xFF lead byte rejected");
         Assert (Websocket.Utf8.Is_Valid (Good), "ASCII accepted");
         Assert (Websocket.Utf8.Is_Valid ((16#C3#, 16#A9#)), "2-byte U+00E9 accepted");
         Assert (not Websocket.Utf8.Is_Valid ((16#C0#, 16#AF#)), "overlong C0 AF rejected");
         Assert (not Websocket.Utf8.Is_Valid ((16#C1#, 16#BF#)), "overlong C1 BF rejected");
         Assert (not Websocket.Utf8.Is_Valid ((16#E0#, 16#80#, 16#AF#)), "overlong E0 80 AF rejected");
         Assert (not Websocket.Utf8.Is_Valid ((16#ED#, 16#A0#, 16#80#)), "surrogate D800 rejected");
         Assert (not Websocket.Utf8.Is_Valid ((16#F4#, 16#90#, 16#80#, 16#80#)), "> U+10FFFF rejected");
         Assert (Websocket.Utf8.Is_Valid ((16#F4#, 16#8F#, 16#BF#, 16#BF#)), "U+10FFFF accepted");
         Assert (not Websocket.Utf8.Is_Valid ((16#F0#, 16#80#, 16#80#, 16#80#)), "overlong 4-byte rejected");
         Assert (not Websocket.Utf8.Is_Valid (Trunc), "truncated sequence rejected");
         Assert (Websocket.Utf8.Is_Valid ((16#F0#, 16#9F#, 16#98#, 16#80#)), "4-byte emoji accepted");
         Assert (not Websocket.Utf8.Is_Valid ((16#C3#, 16#28#)), "bad continuation rejected");

         -- Incremental: split a valid 3-byte char across Append calls
         Websocket.Utf8.Reset (V);
         Assert (Websocket.Utf8.Append (V, 16#E2#), "incremental lead byte ok");
         Assert (Websocket.Utf8.Append (V, 16#9C#), "incremental second byte ok");
         Assert (Websocket.Utf8.Incomplete (V), "mid-sequence reports incomplete");
         Assert (Websocket.Utf8.Append (V, 16#84#), "incremental final byte ok");
         Assert (not Websocket.Utf8.Incomplete (V), "complete sequence not incomplete");

         -- Incremental: overlong sequence detected across split
         Websocket.Utf8.Reset (V);
         Assert (Websocket.Utf8.Append (V, 16#E0#), "overlong lead accepted so far");
         Assert (Websocket.Utf8.Append (V, 16#80#), "overlong second byte accepted so far");
         Assert (not Websocket.Utf8.Append (V, 16#80#),
                 "overlong detected on final byte");
      end;
      New_Line;

   end Run_Tests;

begin
   Run_Tests;
   
   Put_Line ("=====================================");
   Put_Line ("Tests run:" & Test_Count'Image);
   Put_Line ("Failures: " & Fail_Count'Image);
   
   if Fail_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Put_Line ("All tests PASSED.");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
   end if;
end Test_Runner;
