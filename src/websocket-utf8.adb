-- UTF-8 validation implementation (RFC 3629). Rejects:
--   - bytes 16#C0#, 16#C1# (overlong 2-byte encodings of ASCII)
--   - 16#F5#..16#FF# (beyond U+10FFFF or plain invalid)
--   - misplaced continuation bytes (16#80#..16#BF# with no lead pending)
--   - overlong sequences (decoded code point below the minimum for its
--     length: 2 bytes < U+0080, 3 bytes < U+0800, 4 bytes < U+10000)
--   - surrogates U+D800..U+DFFF
-- All limits follow RFC 3629 Table 3-7.

package body Websocket.Utf8 is

   -------------------------------------------------------------------
   -- Reset: start validating a fresh payload
   -------------------------------------------------------------------
   procedure Reset (V : in out Validator) is
   begin
      V := (Need => 0, Min_Code => 0, Code => 0);
   end Reset;

   -------------------------------------------------------------------
   -- Append: feed one byte
   -------------------------------------------------------------------
   function Append (V : in out Validator; B : Stream_Element) return Boolean is
      Byte : constant Unsigned_8 := Unsigned_8 (B);
   begin
      if V.Need = 0 then
         -- Expecting a lead byte (or ASCII)
         if Byte < 16#80# then
            return True;                     -- 1-byte ASCII
         elsif Byte in 16#C2# .. 16#DF# then
            V.Need      := 1;
            V.Min_Code  := 16#80#;
            V.Code      := Unsigned_32 (Byte and 16#1F#);
            return True;
         elsif Byte in 16#E0# .. 16#EF# then
            V.Need      := 2;
            V.Min_Code  := 16#800#;
            V.Code      := Unsigned_32 (Byte and 16#0F#);
            return True;
         elsif Byte in 16#F0# .. 16#F4# then
            V.Need      := 3;
            V.Min_Code  := 16#10000#;
            V.Code      := Unsigned_32 (Byte and 16#07#);
            return True;
         else
            -- 80..BF (stray continuation), C0/C1 (overlong), F5..FF
            return False;
         end if;
      else
         -- Expecting a continuation byte 80..BF
         if Byte not in 16#80# .. 16#BF# then
            return False;
         end if;

         V.Code := Shift_Left (V.Code, 6) or Unsigned_32 (Byte and 16#3F#);
         V.Need := V.Need - 1;

         if V.Need = 0 then
            -- Sequence complete: check overlong and surrogate
            if V.Code < V.Min_Code
              or else V.Code > 16#10FFFF#
              or else (V.Code in 16#D800# .. 16#DFFF#)
            then
               return False;
            end if;
         end if;
         return True;
      end if;
   end Append;

   -------------------------------------------------------------------
   -- Append: feed a whole array
   -------------------------------------------------------------------
   function Append
      (V    : in out Validator;
       Data : Stream_Element_Array)
       return Boolean
   is
   begin
      for I in Data'Range loop
         if not Append (V, Data (I)) then
            return False;
         end if;
      end loop;
      return True;
   end Append;

   -------------------------------------------------------------------
   -- Incomplete: a multi-byte sequence is still open
   -------------------------------------------------------------------
   function Incomplete (V : Validator) return Boolean is
      (V.Need > 0);

   -------------------------------------------------------------------
   -- Is_Valid: one-shot check of a complete payload
   -------------------------------------------------------------------
   function Is_Valid (Data : Stream_Element_Array) return Boolean is
      V : Validator;
   begin
      Reset (V);
      if not Append (V, Data) then
         return False;
      end if;
      return not Incomplete (V);
   end Is_Valid;

end Websocket.Utf8;
