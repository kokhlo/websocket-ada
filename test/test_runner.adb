-- Test runner for Websocket.Frames
-- Plain Ada test suite: prints PASS/FAIL, exits nonzero on failure
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Command_Line;
with Ada.Streams; use Ada.Streams;
with Websocket.Frames; use Websocket.Frames;

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
