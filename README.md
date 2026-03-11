# cl-websocket

A pure Common Lisp WebSocket client library implementing RFC 6455.

## Features

- **Pure Common Lisp** - No external dependencies beyond SBCL
- **RFC 6455 compliant** - Full WebSocket protocol support
- **Thread-safe** - Connection operations are mutex-protected
- **Simple API** - Easy-to-use high-level functions

## Requirements

- SBCL (Steel Bank Common Lisp)
- ASDF

## Installation

Clone the repository and load with ASDF:

```lisp
(asdf:load-system :cl-websocket)
```

## Quick Start

```lisp
(use-package :cl-websocket)

;; Connect to a WebSocket server
(let ((ws (connect "echo.websocket.org" 80 :path "/")))
  (unwind-protect
      (progn
        ;; Send a text message
        (send-text ws "Hello, WebSocket!")

        ;; Receive response
        (multiple-value-bind (data type) (receive ws)
          (format t "Received ~A: ~A~%" type data)))

    ;; Always close the connection
    (close-connection ws)))
```

Or use the `with-websocket` macro for automatic cleanup:

```lisp
(with-websocket (ws "echo.websocket.org" 80 :path "/")
  (send-text ws "Hello!")
  (receive ws))
```

## API Reference

### Connection

- `(connect host port &key path protocols extensions origin)` - Connect to a WebSocket server
- `(close-connection connection &key code reason)` - Close a connection gracefully
- `(connection-open-p connection)` - Check if connection is open

### Sending Data

- `(send-text connection text)` - Send a text message
- `(send-binary connection data)` - Send binary data
- `(send-ping connection &optional payload)` - Send a ping frame

### Receiving Data

- `(receive connection &key timeout)` - Receive a message, returns `(values data type)`
  - `type` is one of `:text`, `:binary`, or `:close`

### Frame Encoding/Decoding (Low-level)

- `(encode-text-frame text &key fin mask)` - Encode text as WebSocket frame
- `(encode-binary-frame data &key fin mask)` - Encode binary as WebSocket frame
- `(encode-close-frame code &optional reason)` - Encode close frame
- `(encode-ping-frame &optional payload)` - Encode ping frame
- `(encode-pong-frame payload)` - Encode pong frame
- `(decode-frame data &key start)` - Decode a WebSocket frame

### Constants

**Opcodes:**
- `+opcode-continuation+` (0)
- `+opcode-text+` (1)
- `+opcode-binary+` (2)
- `+opcode-close+` (8)
- `+opcode-ping+` (9)
- `+opcode-pong+` (10)

**Close Codes:**
- `+close-normal+` (1000)
- `+close-going-away+` (1001)
- `+close-protocol-error+` (1002)
- `+close-unsupported-data+` (1003)
- `+close-invalid-payload+` (1007)
- `+close-policy-violation+` (1008)
- `+close-message-too-big+` (1009)
- `+close-internal-error+` (1011)

## Testing

```lisp
(asdf:test-system :cl-websocket)
```

Or manually:

```lisp
(asdf:load-system :cl-websocket)
(cl-websocket-test:run-tests)
```

## Architecture

```
cl-websocket/
  cl-websocket.asd    ; System definition
  package.lisp        ; Package exports
  src/
    util.lisp         ; Base64, SHA-1, byte utilities
    frame.lisp        ; Frame encoding/decoding (RFC 6455 Section 5)
    handshake.lisp    ; Opening handshake (RFC 6455 Section 4)
    connection.lisp   ; Connection management
    client.lisp       ; High-level client API
  test/
    test-websocket.lisp
```

## Protocol Compliance

This library implements:
- RFC 6455 Section 4 - Opening Handshake
- RFC 6455 Section 5 - Data Framing
- RFC 6455 Section 5.3 - Client-to-Server Masking
- RFC 6455 Section 5.4 - Fragmentation
- RFC 6455 Section 5.5 - Control Frames
- RFC 6455 Section 7 - Closing the Connection

## License

MIT License - see LICENSE file.
