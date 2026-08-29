-- Base64 implementation (RFC 4648)
with Interfaces; use Interfaces;

package body Websocket.Base64 is

   Alphabet : constant String :=
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

   -- Value of a base64 digit, or 16#FF# if not a valid digit
   function Digit_Value (C : Character) return Unsigned_8 is
   begin
      case C is
         when 'A' .. 'Z' => return Character'Pos (C) - Character'Pos ('A');
         when 'a' .. 'z' => return Character'Pos (C) - Character'Pos ('a') + 26;
         when '0' .. '9' => return Character'Pos (C) - Character'Pos ('0') + 52;
         when '+'        => return 62;
         when '/'        => return 63;
         when others     => return 16#FF#;
      end case;
   end Digit_Value;

   -------------------------------------------------------------------
   -- Encode: binary → base64 text (RFC 4648 §4)
   -------------------------------------------------------------------
   function Encode (Data : Stream_Element_Array) return String is
      -- Number of complete 3-byte groups
      Group_Count : constant Natural := Natural (Data'Length / 3);
      Result : String (1 .. Natural (Unsigned_64 (Data'Length + 2) / 3) * 4);
      Pos    : Natural := 0;

      -- Append the 4 characters for one 3-byte group starting at I
      procedure Emit_Group (I : Stream_Element_Offset) is
         B0 : constant Unsigned_32 := Unsigned_32 (Data (I));
         B1 : constant Unsigned_32 := Unsigned_32 (Data (I + 1));
         B2 : constant Unsigned_32 := Unsigned_32 (Data (I + 2));
         Triple : constant Unsigned_32 :=
            Shift_Left (B0, 16) or Shift_Left (B1, 8) or B2;
      begin
         Result (Pos + 1) := Alphabet (Natural (Shift_Right (Triple, 18) and 16#3F#) + 1);
         Result (Pos + 2) := Alphabet (Natural (Shift_Right (Triple, 12) and 16#3F#) + 1);
         Result (Pos + 3) := Alphabet (Natural (Shift_Right (Triple, 6) and 16#3F#) + 1);
         Result (Pos + 4) := Alphabet (Natural (Triple and 16#3F#) + 1);
         Pos := Pos + 4;
      end Emit_Group;

   begin
      -- Complete 3-byte groups
      for G in 0 .. Group_Count - 1 loop
         Emit_Group (Data'First + Stream_Element_Offset (G * 3));
      end loop;

      -- Trailing 1 or 2 bytes, padded to 4 characters
      case Data'Length mod 3 is
         when 0 =>
            null;
         when 1 =>
            declare
               B0 : constant Unsigned_32 := Unsigned_32 (Data (Data'Last));
               Triple : constant Unsigned_32 := Shift_Left (B0, 16);
            begin
               Result (Pos + 1) := Alphabet (Natural (Shift_Right (Triple, 18) and 16#3F#) + 1);
               Result (Pos + 2) := Alphabet (Natural (Shift_Right (Triple, 12) and 16#3F#) + 1);
               Result (Pos + 3) := '=';
               Result (Pos + 4) := '=';
            end;
         when others =>  -- only 2 remains
            declare
               B0 : constant Unsigned_32 := Unsigned_32 (Data (Data'Last - 1));
               B1 : constant Unsigned_32 := Unsigned_32 (Data (Data'Last));
               Triple : constant Unsigned_32 :=
                  Shift_Left (B0, 16) or Shift_Left (B1, 8);
            begin
               Result (Pos + 1) := Alphabet (Natural (Shift_Right (Triple, 18) and 16#3F#) + 1);
               Result (Pos + 2) := Alphabet (Natural (Shift_Right (Triple, 12) and 16#3F#) + 1);
               Result (Pos + 3) := Alphabet (Natural (Shift_Right (Triple, 6) and 16#3F#) + 1);
               Result (Pos + 4) := '=';
            end;
      end case;

      return Result;
   end Encode;

   -------------------------------------------------------------------
   -- Try_Decode: base64 text → binary (RFC 4648 §4)
   -------------------------------------------------------------------
   function Try_Decode
      (Item   : String;
       Result : out Stream_Element_Array;
       Last   : out Stream_Element_Offset)
      return Boolean
   is
      Group_Count : constant Natural := Item'Length / 4;
      Padding     : Natural := 0;
      Out_Pos     : Stream_Element_Offset := Result'First - 1;

      -- Convert one 4-character group into up to 3 bytes
      function Convert_Group
         (G : Natural)
         return Boolean
      is
         V : array (0 .. 3) of Unsigned_8 := (others => 0);
         Chars : array (0 .. 3) of Character;
      begin
         for J in 0 .. 3 loop
            Chars (J) := Item (Item'First + G * 4 + J);
         end loop;

         -- Only the end of the string may carry '=' padding (RFC 4648 §3.2)
         for J in 0 .. 3 loop
            if Chars (J) = '=' and then G * 4 + J < (Group_Count - 1) * 4 then
               return False;
            end if;
         end loop;

         for J in 0 .. 3 loop
            if Chars (J) = '=' then
               Padding := Padding + 1;
               if Padding > 2 or else J < 2 then
                  return False;  -- '=', only 1-2 of them, only in the last group
               end if;
            else
               V (J) := Digit_Value (Chars (J));
               if V (J) = 16#FF# then
                  return False;
               end if;
            end if;
         end loop;

         -- Rejected above when '=' appears too early; from here the group is
         -- either padding-free or 'xxy=' / 'xx==' shaped.
         if Padding = 1 and then Chars (3) /= '=' then
            return False;  -- non-canonical 'A=BC'-style padding (RFC 4648 §3.5)
         end if;
         if Padding = 0 then
            -- Four 6-bit values → three 8-bit bytes
            Out_Pos := Out_Pos + 1;
            Result (Out_Pos) := Stream_Element
               (Shift_Left (Unsigned_32 (V (0)), 2)
                  or Shift_Right (Unsigned_32 (V (1)), 4));
            Out_Pos := Out_Pos + 1;
            Result (Out_Pos) := Stream_Element
               (Shift_Left (Unsigned_32 (V (1)) and 16#0F#, 4)
                  or Shift_Right (Unsigned_32 (V (2)), 2));
            Out_Pos := Out_Pos + 1;
            Result (Out_Pos) := Stream_Element
               (Shift_Left (Unsigned_32 (V (2)) and 16#03#, 6)
                  or Unsigned_32 (V (3)));
         elsif Padding = 1 then
            -- "xxy=" → 2 bytes
            Out_Pos := Out_Pos + 1;
            Result (Out_Pos) := Stream_Element
               (Shift_Left (Unsigned_32 (V (0)), 2)
                  or Shift_Right (Unsigned_32 (V (1)), 4));
            Out_Pos := Out_Pos + 1;
            Result (Out_Pos) := Stream_Element
               (Shift_Left (Unsigned_32 (V (1)) and 16#0F#, 4)
                  or Shift_Right (Unsigned_32 (V (2)), 2));
         else
            -- "xx==" → 1 byte
            Out_Pos := Out_Pos + 1;
            Result (Out_Pos) := Stream_Element
               (Shift_Left (Unsigned_32 (V (0)), 2)
                  or Shift_Right (Unsigned_32 (V (1)), 4));
         end if;
         return True;
      end Convert_Group;

   begin
      Last := Result'First - 1;

      -- Length must be a multiple of 4 (with padding), RFC 4648 §3.2
      if Item'Length mod 4 /= 0 then
         return False;
      end if;
      if Item'Length = 0 then
         return True;
      end if;

      for G in 0 .. Group_Count - 1 loop
         if not Convert_Group (G) then
            Last := Result'First - 1;
            return False;
         end if;
      end loop;

      if Out_Pos > Result'Last then
         Last := Result'First - 1;
         return False;  -- output does not fit
      end if;
      Last := Out_Pos;
      return True;
   end Try_Decode;

   -------------------------------------------------------------------
   -- Decode: convenience wrapper allocating an exact-size result
   -------------------------------------------------------------------
   function Decode (Item : String) return Stream_Element_Array is
      Max_Len : constant Stream_Element_Offset :=
         Stream_Element_Offset ((Item'Length / 4) * 3);
   begin
      if Item'Length mod 4 /= 0 then
         return (1 .. 0 => 0);
      end if;

      declare
         Buf : Stream_Element_Array (1 .. Max_Len);
         Last : Stream_Element_Offset;
      begin
         if Try_Decode (Item, Buf, Last) then
            return Buf (1 .. Last);
         else
            return (1 .. 0 => 0);
         end if;
      end;
   end Decode;

end Websocket.Base64;
