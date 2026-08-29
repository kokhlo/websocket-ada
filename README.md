# websocket-ada

RFC 6455 WebSocket client library for Ada.

## Status

**Work in Progress** — Frame codec + handshake complete, TCP connection layer next.

Current implementation:
- ✅ RFC 6455 frame codec (encode/decode)
- ✅ All frame types (text, binary, control frames)
- ✅ 7-bit, 16-bit, and 64-bit length encoding
- ✅ Client masking (RFC 6455 §5.3)
- ✅ Control frame validation (≤125 bytes)
- ✅ Incremental parsing (Need_More_Data state)
- ✅ HTTP handshake layer (RFC 6455 §4.1, §4.2.2)
- ✅ Sec-WebSocket-Accept computation (SHA-1 + Base64)
- ✅ Server response validation (status 101, case-insensitive headers, Connection token list)
- ✅ 52 tests (30 frame codec + 22 handshake), all passing

Coming next:
- TCP connection layer (GNAT.Sockets)
- Send/receive loop with automatic Ping/Pong
- Close handshake (RFC 6455 §5.5.1)

## Why websocket-ada?

No standalone WebSocket client library exists for Ada. The only implementations are:
- AWS (Ada Web Server) — a 300k-LOC framework, overkill for simple WebSocket clients
- sparre/Black (2017, archived, 18 stars) — unmaintained

This library provides a lightweight, standalone WebSocket client for Ada projects.

## Dependencies

None beyond GNAT runtime. Base64 is self-contained; SHA-1 uses GNAT.SHA1 (part of the compiler runtime). No external C libraries, no AWS framework.

## Building

```bash
# With Alire
alr build

# With gprbuild
gprbuild -p -P websocket_ada.gpr

# Run tests
gprbuild -p -P websocket_tests.gpr
./obj_test/test_runner

gprbuild -p -P websocket_handshake_tests.gpr
./obj_test_handshake/test_handshake
```

## Example

```ada
with Websocket.Frames; use Websocket.Frames;

-- Create a text frame (client must mask)
F : Frame := (
   FIN => True,
   Opcode => Text,
   Masked => True,
   Masking_Key => (16#12#, 16#34#, 16#56#, 16#78#),
   Payload => <>
);
F.Payload.Append (Character'Pos ('H'));
F.Payload.Append (Character'Pos ('i'));

-- Encode to wire format
Buffer : Payload_Data;
Encode (F, Buffer);

-- Decode from wire format
Decoded : Frame;
Consumed : Stream_Element_Count;
Status : Decode_Status;
Decode (Buffer, Decoded, Consumed, Status);
```

## License

MIT License — see LICENSE file.

## Author

Konstantin Khlopkov ([@kokhlo](https://github.com/kokhlo))
