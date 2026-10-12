# websocket-ada

[![CI](https://github.com/kokhlo/websocket-ada/actions/workflows/build-test.yml/badge.svg)](https://github.com/kokhlo/websocket-ada/actions/workflows/build-test.yml)

RFC 6455 WebSocket client library for Ada.

## Status

**Work in Progress** — Frame codec + handshake complete, TCP connection layer next. Latest release: **v0.3.0**.

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
- ✅ Receiver-side validation: RSV bits, reserved opcodes, fragmented control frames rejected (§5.2, §5.5, §7.2)
- ✅ `Decode_Client`: server frames must be unmasked (§5.1); close payload validated — code ranges + UTF-8 reason (§5.5.1)
- ✅ Strict UTF-8 validation (RFC 3629): overlongs, surrogates, > U+10FFFF, incremental state
- ✅ 99 tests (77 frame codec/UTF-8 + 22 handshake), all passing

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

## Installation

With [Alire](https://alire.ada.dev):

```bash
alr with websocket
```

> Available in the community index since v0.2.0 ([alire-index PR #2148](https://github.com/alire-project/alire-index/pull/2148)).

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

## Roadmap

- [x] RFC 6455 frame codec (all frame types, 7/16/64-bit lengths, client masking)
- [x] HTTP upgrade handshake (Sec-WebSocket-Accept, response validation)
- [ ] TCP connection layer with automatic Ping/Pong — next
- [ ] Automatic reconnection with exponential backoff
- [ ] Per-message compression (`permessage-deflate`, RFC 7692) — v0.3

## License

MIT License — see LICENSE file.

## Author

Konstantin Khlopkov ([@kokhlo](https://github.com/kokhlo))
