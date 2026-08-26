-- RFC 6455 WebSocket frame codec: encoding and decoding of WebSocket frames
with Ada.Streams; use Ada.Streams;
with Ada.Containers.Vectors;

package Websocket.Frames is

   -- RFC 6455 §5.2 opcodes
   type Opcode_Type is (
      Continuation,  -- 0x0
      Text,          -- 0x1
      Binary,        -- 0x2
      Reserved_3,    -- 0x3
      Reserved_4,    -- 0x4
      Reserved_5,    -- 0x5
      Reserved_6,    -- 0x6
      Reserved_7,    -- 0x7
      Close,         -- 0x8
      Ping,          -- 0x9
      Pong,          -- 0xA
      Reserved_B,    -- 0xB
      Reserved_C,    -- 0xC
      Reserved_D,    -- 0xD
      Reserved_E,    -- 0xE
      Reserved_F     -- 0xF
   );
   for Opcode_Type use (
      Continuation => 16#0#,
      Text         => 16#1#,
      Binary       => 16#2#,
      Reserved_3   => 16#3#,
      Reserved_4   => 16#4#,
      Reserved_5   => 16#5#,
      Reserved_6   => 16#6#,
      Reserved_7   => 16#7#,
      Close        => 16#8#,
      Ping         => 16#9#,
      Pong         => 16#A#,
      Reserved_B   => 16#B#,
      Reserved_C   => 16#C#,
      Reserved_D   => 16#D#,
      Reserved_E   => 16#E#,
      Reserved_F   => 16#F#
   );
   for Opcode_Type'Size use 4;

   -- Payload data container
   package Payload_Vectors is new Ada.Containers.Vectors
      (Index_Type   => Natural,
       Element_Type => Stream_Element);
   
   subtype Payload_Data is Payload_Vectors.Vector;

   -- Masking key: 4 bytes for client-to-server frames (RFC 6455 §5.3)
   type Masking_Key_Type is array (0 .. 3) of Stream_Element;

   -- WebSocket frame structure (RFC 6455 §5.2)
   type Frame is record
      FIN      : Boolean := True;              -- Final fragment flag
      RSV1     : Boolean := False;             -- Reserved bit 1 (extension)
      RSV2     : Boolean := False;             -- Reserved bit 2 (extension)
      RSV3     : Boolean := False;             -- Reserved bit 3 (extension)
      Opcode   : Opcode_Type := Text;          -- Frame opcode
      Masked   : Boolean := False;             -- Masking flag
      Payload_Length : Stream_Element_Count := 0;  -- Payload length
      Masking_Key    : Masking_Key_Type := (others => 0);  -- Masking key
      Payload        : Payload_Data;           -- Payload data
   end record;

   -- Decode status
   type Decode_Status is (
      Success,           -- Frame decoded successfully
      Need_More_Data,    -- Buffer incomplete, need more bytes
      Protocol_Error     -- RFC 6455 violation detected
   );

   -- Encode a frame into a byte stream
   -- CLIENT frames must be masked (Masked => True)
   -- SERVER frames must NOT be masked (Masked => False)
   procedure Encode
      (F      : in  Frame;
       Buffer : out Payload_Data);

   -- Decode a frame from a byte stream
   -- Returns partial results: Status indicates success/need-more/error
   -- Consumed indicates how many bytes were consumed from Buffer
   procedure Decode
      (Buffer   : in  Payload_Data;
       F        : out Frame;
       Consumed : out Stream_Element_Count;
       Status   : out Decode_Status);

   -- Apply/remove masking (RFC 6455 §5.3)
   -- XOR each payload byte with masking_key[i mod 4]
   procedure Apply_Mask
      (Payload : in out Payload_Data;
       Key     : in Masking_Key_Type);

   -- Check if opcode is a control frame (RFC 6455 §5.5)
   function Is_Control_Frame (Op : Opcode_Type) return Boolean;

end Websocket.Frames;
