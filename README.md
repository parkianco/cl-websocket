# Websocket

Minimal RFC 6455 frame encoding and decoding utilities for Common Lisp.

## Features

- Create text frames
- Encode and decode masked or unmasked websocket frames
- Mask and unmask payload bytes using the RFC 6455 XOR step

## Installation

```lisp
(asdf:load-system :cl-websocket)
```

## Usage

```lisp
(let* ((frame (cl-websocket:make-text-frame "Hello"))
       (wire-bytes (cl-websocket:encode-frame frame)))
  (cl-websocket:decode-frame wire-bytes))
```

## Testing

```lisp
(asdf:test-system :cl-websocket)
```

## API

- `make-text-frame` builds a simple websocket text frame.
- `encode-frame` serializes a `websocket-frame` to wire bytes.
- `decode-frame` parses wire bytes into a `websocket-frame`.
- `mask-payload` and `unmask-payload` apply websocket masking.

## License

BSD-3-Clause License - See LICENSE file for details.

---
Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
SPDX-License-Identifier: BSD-3-Clause
