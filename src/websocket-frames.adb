-- RFC 6455 WebSocket frame codec implementation
with Interfaces; use Interfaces;
with Websocket.Utf8;

package body Websocket.Frames is

   -- Convert Opcode_Type to 4-bit value
   function Opcode_To_Byte (Op : Opcode_Type) return Stream_Element is
      (Stream_Element (Opcode_Type'Pos (Op)));

   -- Convert 4-bit value to Opcode_Type
   function Byte_To_Opcode (B : Stream_Element) return Opcode_Type is
      (Opcode_Type'Val (B and 16#0F#));

   -------------------------------------------------------------------
   -- Encode: Frame → byte stream (RFC 6455 §5.2)
   -------------------------------------------------------------------
   procedure Encode
      (F      : in  Frame;
       Buffer : out Payload_Data)
   is
      Byte0, Byte1 : Stream_Element;
      Len : constant Stream_Element_Count := Stream_Element_Count (F.Payload.Length);
   begin
      Buffer.Clear;

      -- Byte 0: FIN, RSV1-3, Opcode (RFC 6455 §5.2)
      Byte0 := 0;
      if F.FIN then
         Byte0 := Byte0 or 16#80#;
      end if;
      if F.RSV1 then
         Byte0 := Byte0 or 16#40#;
      end if;
      if F.RSV2 then
         Byte0 := Byte0 or 16#20#;
      end if;
      if F.RSV3 then
         Byte0 := Byte0 or 16#10#;
      end if;
      Byte0 := Byte0 or Opcode_To_Byte (F.Opcode);
      Buffer.Append (Byte0);

      -- Byte 1: MASK bit, payload length (RFC 6455 §5.2)
      Byte1 := 0;
      if F.Masked then
         Byte1 := Byte1 or 16#80#;
      end if;

      -- Payload length encoding (7-bit, 16-bit extended, 64-bit extended)
      if Len < 126 then
         -- 7-bit length
         Byte1 := Byte1 or Stream_Element (Len);
         Buffer.Append (Byte1);
      elsif Len < 65536 then
         -- 16-bit extended length (126 marker + 2 bytes)
         Byte1 := Byte1 or 126;
         Buffer.Append (Byte1);
         -- Big-endian 16-bit length
         Buffer.Append (Stream_Element (Shift_Right (Unsigned_64 (Len), 8) and 16#FF#));
         Buffer.Append (Stream_Element (Unsigned_64 (Len) and 16#FF#));
      else
         -- 64-bit extended length (127 marker + 8 bytes)
         Byte1 := Byte1 or 127;
         Buffer.Append (Byte1);
         -- Big-endian 64-bit length
         for Shift in reverse 0 .. 7 loop
            Buffer.Append (Stream_Element (Shift_Right (Unsigned_64 (Len), Shift * 8) and 16#FF#));
         end loop;
      end if;

      -- Masking key (4 bytes if masked)
      if F.Masked then
         for I in F.Masking_Key'Range loop
            Buffer.Append (F.Masking_Key (I));
         end loop;
      end if;

      -- Payload data (masked if necessary)
      if Len > 0 then
         if F.Masked then
            -- Apply mask before appending
            declare
               Masked_Payload : Payload_Data := F.Payload;
            begin
               Apply_Mask (Masked_Payload, F.Masking_Key);
               for I in 0 .. Natural (Len) - 1 loop
                  Buffer.Append (Masked_Payload.Element (I));
               end loop;
            end;
         else
            -- Unmasked payload
            for I in 0 .. Natural (Len) - 1 loop
               Buffer.Append (F.Payload.Element (I));
            end loop;
         end if;
      end if;
   end Encode;

   -------------------------------------------------------------------
   -- Decode: byte stream → Frame (RFC 6455 §5.2)
   -------------------------------------------------------------------
   procedure Decode
      (Buffer   : in  Payload_Data;
       F        : out Frame;
       Consumed : out Stream_Element_Count;
       Status   : out Decode_Status)
   is
      Pos : Stream_Element_Count := 0;
      Byte0, Byte1 : Stream_Element;
      Payload_Len : Unsigned_64;
      Mask_Bit : Boolean;
   begin
      Consumed := 0;
      Status := Need_More_Data;

      -- Need at least 2 bytes for header
      if Stream_Element_Count (Buffer.Length) < 2 then
         return;
      end if;

      -- Byte 0: FIN, RSV1-3, Opcode
      Byte0 := Buffer.Element (Natural (Pos));
      Pos := Pos + 1;
      F.FIN := (Byte0 and 16#80#) /= 0;
      F.RSV1 := (Byte0 and 16#40#) /= 0;
      F.RSV2 := (Byte0 and 16#20#) /= 0;
      F.RSV3 := (Byte0 and 16#10#) /= 0;
      F.Opcode := Byte_To_Opcode (Byte0 and 16#0F#);

      -- RSV bits must be zero unless an extension is negotiated; the
      -- client library negotiates none, so any set bit fails the
      -- connection (RFC 6455 §5.2, §7.2).
      if F.RSV1 or F.RSV2 or F.RSV3 then
         Status := Protocol_Error;
         return;
      end if;

      -- Reserved opcodes are a protocol error without a negotiated
      -- extension (RFC 6455 §5.2, §7.2)
      if Is_Reserved_Opcode (F.Opcode) then
         Status := Protocol_Error;
         return;
      end if;

      -- Byte 1: MASK bit, payload length
      Byte1 := Buffer.Element (Natural (Pos));
      Pos := Pos + 1;
      Mask_Bit := (Byte1 and 16#80#) /= 0;
      F.Masked := Mask_Bit;
      Payload_Len := Unsigned_64 (Byte1 and 16#7F#);

      -- Extended payload length (16-bit or 64-bit)
      if Payload_Len = 126 then
         -- 16-bit extended length
         if Stream_Element_Count (Buffer.Length) < Pos + 2 then
            return;  -- Need more data
         end if;
         Payload_Len := Shift_Left (Unsigned_64 (Buffer.Element (Natural (Pos))), 8)
                      or Unsigned_64 (Buffer.Element (Natural (Pos + 1)));
         Pos := Pos + 2;
      elsif Payload_Len = 127 then
         -- 64-bit extended length
         if Stream_Element_Count (Buffer.Length) < Pos + 8 then
            return;  -- Need more data
         end if;
         Payload_Len := 0;
         for I in 0 .. 7 loop
            Payload_Len := Shift_Left (Payload_Len, 8)
                         or Unsigned_64 (Buffer.Element (Natural (Pos + Stream_Element_Count (I))));
         end loop;
         Pos := Pos + 8;
      end if;

      -- RFC 6455 §5.5: all control frames must have FIN set and payload
      -- ≤ 125 bytes; a fragmented or oversized control frame is a
      -- protocol error.
      if Is_Control_Frame (F.Opcode) then
         if not F.FIN then
            Status := Protocol_Error;
            return;
         end if;
         if Payload_Len > 125 then
            Status := Protocol_Error;
            return;
         end if;
      end if;

      -- A 64-bit length may announce more bytes than a
      -- Stream_Element_Count can address; reject instead of crashing
      -- on the conversion.
      if Payload_Len > Unsigned_64 (Max_Payload_Length) then
         Status := Protocol_Error;
         return;
      end if;

      F.Payload_Length := Stream_Element_Count (Payload_Len);

      -- Masking key (4 bytes if masked)
      if Mask_Bit then
         if Stream_Element_Count (Buffer.Length) < Pos + 4 then
            return;  -- Need more data
         end if;
         for I in F.Masking_Key'Range loop
            F.Masking_Key (I) := Buffer.Element (Natural (Pos) + I);
         end loop;
         Pos := Pos + 4;
      end if;

      -- Payload data
      if Stream_Element_Count (Buffer.Length) < Pos + Stream_Element_Count (Payload_Len) then
         return;  -- Need more data
      end if;

      F.Payload.Clear;
      for I in 0 .. Natural (Payload_Len) - 1 loop
         F.Payload.Append (Buffer.Element (Natural (Pos) + I));
      end loop;
      Pos := Pos + Stream_Element_Count (Payload_Len);

      -- Unmask payload if masked
      if Mask_Bit then
         Apply_Mask (F.Payload, F.Masking_Key);
      end if;

      Consumed := Pos;
      Status := Success;
   end Decode;

   -------------------------------------------------------------------
   -- Decode_Client: decode + client-receiver rules (RFC 6455 §5.1, §5.5.1)
   -------------------------------------------------------------------
   procedure Decode_Client
      (Buffer   : in  Payload_Data;
       F        : out Frame;
       Consumed : out Stream_Element_Count;
       Status   : out Decode_Status)
   is
   begin
      Decode (Buffer, F, Consumed, Status);
      if Status /= Success then
         return;
      end if;

      -- §5.1: a server MUST NOT mask frames sent to the client
      if F.Masked then
         Status := Protocol_Error;
         return;
      end if;

      -- §5.5.1: close payload is [] | code | code + UTF-8 reason
      if F.Opcode = Close then
         declare
            Len : constant Natural := Natural (F.Payload.Length);
         begin
            if Len = 1 then
               Status := Protocol_Error;      -- truncated code
               return;
            end if;
            if Len >= 2 then
               declare
                  Code : constant Unsigned_32 :=
                     Shift_Left (Unsigned_32 (F.Payload.Element (0)), 8)
                     or Unsigned_32 (F.Payload.Element (1));
                  Code_OK : constant Boolean :=
                     (Code in 1000 .. 1003 or else Code in 1007 .. 1011)
                     or else Code in 3000 .. 4999;
                  Reason : Stream_Element_Array (1 .. Stream_Element_Offset (Len - 2));
               begin
                  if not Code_OK then
                     Status := Protocol_Error;
                     return;
                  end if;
                  -- bytes 2 .. Len-1 of the payload (0-based) are the reason
                  for I in 0 .. Len - 3 loop
                     Reason (Stream_Element_Offset (I + 1)) :=
                        F.Payload.Element (2 + I);
                  end loop;
                  if not Websocket.Utf8.Is_Valid (Reason) then
                     Status := Protocol_Error;
                     return;
                  end if;
               end;
            end if;
         end;
      end if;
   end Decode_Client;

   -------------------------------------------------------------------
   -- Apply_Mask: XOR payload with 4-byte key (RFC 6455 §5.3)
   -------------------------------------------------------------------
   procedure Apply_Mask
      (Payload : in out Payload_Data;
       Key     : in Masking_Key_Type)
   is
   begin
      for I in 0 .. Natural (Payload.Length) - 1 loop
         declare
            Original : constant Stream_Element := Payload.Element (I);
            Masked : constant Stream_Element := Original xor Key (I mod 4);
         begin
            Payload.Replace_Element (I, Masked);
         end;
      end loop;
   end Apply_Mask;

   -------------------------------------------------------------------
   -- Is_Control_Frame: check if opcode is a control frame
   -------------------------------------------------------------------
   function Is_Control_Frame (Op : Opcode_Type) return Boolean is
      (Op = Close or Op = Ping or Op = Pong);

   -------------------------------------------------------------------
   -- Is_Reserved_Opcode: opcodes 0x3-0x7 and 0xB-0xF (RFC 6455 §5.2)
   -------------------------------------------------------------------
   function Is_Reserved_Opcode (Op : Opcode_Type) return Boolean is
      (Op in Reserved_3 .. Reserved_7 or else Op in Reserved_B .. Reserved_F);

end Websocket.Frames;
