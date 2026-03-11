;;;; package.lisp - Package definition for cl-websocket
;;;;
;;;; RFC 6455 WebSocket Protocol Library
;;;; Pure Common Lisp - no external dependencies

(in-package #:cl-user)

(defpackage #:cl-websocket
  (:use #:cl)
  (:documentation
   "RFC 6455 WebSocket Protocol Library.

    Pure Common Lisp implementation using only SBCL built-ins.
    Provides frame encoding/decoding, handshake, and client functionality.

    Thread Safety: All public functions are thread-safe.
    Dependencies: None (uses sb-bsd-sockets, sb-thread)")

  ;; Constants - Protocol
  (:export #:+ws-version+
           #:+ws-guid+)

  ;; Constants - Opcodes
  (:export #:+opcode-continuation+
           #:+opcode-text+
           #:+opcode-binary+
           #:+opcode-close+
           #:+opcode-ping+
           #:+opcode-pong+)

  ;; Constants - Close codes
  (:export #:+close-normal+
           #:+close-going-away+
           #:+close-protocol-error+
           #:+close-unsupported-data+
           #:+close-invalid-payload+
           #:+close-policy-violation+
           #:+close-message-too-big+
           #:+close-internal-error+)

  ;; Constants - States
  (:export #:+state-connecting+
           #:+state-open+
           #:+state-closing+
           #:+state-closed+)

  ;; Frame structure
  (:export #:ws-frame
           #:ws-frame-p
           #:make-ws-frame
           #:ws-frame-fin
           #:ws-frame-opcode
           #:ws-frame-masked
           #:ws-frame-payload-length
           #:ws-frame-mask-key
           #:ws-frame-payload)

  ;; Connection structure
  (:export #:ws-connection
           #:ws-connection-p
           #:ws-connection-state
           #:ws-connection-socket
           #:ws-connection-stream)

  ;; Frame encoding/decoding
  (:export #:encode-frame
           #:decode-frame
           #:encode-text-frame
           #:encode-binary-frame
           #:encode-close-frame
           #:encode-ping-frame
           #:encode-pong-frame
           #:mask-payload
           #:unmask-payload
           #:generate-mask-key)

  ;; Handshake
  (:export #:compute-accept-key
           #:generate-client-key
           #:make-handshake-request
           #:parse-handshake-response
           #:validate-handshake-response)

  ;; Client
  (:export #:connect
           #:close-connection
           #:send-text
           #:send-binary
           #:send-ping
           #:receive
           #:connection-open-p)

  ;; Utilities
  (:export #:sha1
           #:base64-encode
           #:base64-decode
           #:string-to-octets
           #:octets-to-string
           #:random-bytes)

  ;; Conditions
  (:export #:websocket-error
           #:websocket-connection-error
           #:websocket-protocol-error
           #:websocket-handshake-error))
