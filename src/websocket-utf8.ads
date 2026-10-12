-- UTF-8 validation (RFC 3629) for WebSocket payloads.
-- RFC 6455 requires the close reason (§5.5.1) and text message payloads
-- (§5.6, §8.1) to be valid UTF-8; a peer sending invalid UTF-8 fails the
-- connection. This unit provides strict, incremental (resumable)
-- validation so a caller can feed payload chunks as they arrive and get
-- a "need more bytes" verdict for a trailing partial sequence.

with Ada.Streams; use Ada.Streams;
with Interfaces;  use Interfaces;

package Websocket.Utf8 is
   pragma Pure;

   -- Validation state, kept between Append calls so a payload split
   -- across reads can be validated incrementally.
   type Validator is private;

   -- Restart validation for a new payload.
   procedure Reset (V : in out Validator);

   -- Feed one byte to the validator. Returns False when the byte
   -- completes an invalid sequence: the payload is not valid UTF-8 and
   -- validation cannot continue.
   function Append (V : in out Validator; B : Stream_Element) return Boolean;

   -- Feed a whole array of bytes. Returns False on the first invalid
   -- byte; V is left in its error state.
   function Append
      (V    : in out Validator;
       Data : Stream_Element_Array)
       return Boolean;

   -- True when V is waiting for continuation bytes of an incomplete
   -- (but so far valid) multi-byte sequence. Call this after the last
   -- byte: True means the payload ended mid-character and is invalid.
   function Incomplete (V : Validator) return Boolean;

   -- One-shot convenience: the whole payload is valid UTF-8.
   function Is_Valid (Data : Stream_Element_Array) return Boolean;

private

   -- Decoder state:
   --   Need      : how many continuation bytes are still expected
   --   Remaining : total bytes of the current sequence still expected
   --   Min_Code  : lowest code point that would NOT be overlong for
   --               the sequence length seen so far (RFC 3629 Table 3-7)
   --   Code      : code point accumulated so far
   type Validator is record
      Need      : Natural range 0 .. 3 := 0;
      Min_Code  : Unsigned_32 := 0;
      Code      : Unsigned_32 := 0;
   end record;

end Websocket.Utf8;
