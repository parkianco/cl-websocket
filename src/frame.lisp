;;;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;;;; SPDX-License-Identifier: Apache-2.0

;;;; frame.lisp - WebSocket frame encoding and decoding
;;;;
;;;; Implements the binary framing protocol per RFC 6455 Section 5.
;;;; Handles frame header parsing, payload masking/unmasking, and fragmentation.
;;;;
;;;; Standards: RFC 6455 Section 5 (Data Framing)
;;;; Thread Safety: Pure functions, no shared state
;;;; Performance: O(n) for encoding/decoding where n is payload size

(in-package #:cl-websocket)

;;; ============================================================================
;;; Constants
;;; ============================================================================

;; Protocol version
(defconstant +ws-version+ 13
  "WebSocket protocol version per RFC 6455.")

;; Magic GUID for handshake key computation
(defvar +ws-guid+ "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  "WebSocket GUID used for Sec-WebSocket-Accept key computation.")

;; Opcodes (RFC 6455 Section 5.2)
(defconstant +opcode-continuation+ #x0 "Continuation frame.")
(defconstant +opcode-text+ #x1 "Text frame (UTF-8).")
(defconstant +opcode-binary+ #x2 "Binary frame.")
(defconstant +opcode-close+ #x8 "Connection close.")
(defconstant +opcode-ping+ #x9 "Ping frame.")
(defconstant +opcode-pong+ #xA "Pong frame.")

;; Close codes (RFC 6455 Section 7.4.1)
(defconstant +close-normal+ 1000 "Normal closure.")
(defconstant +close-going-away+ 1001 "Endpoint going away.")
(defconstant +close-protocol-error+ 1002 "Protocol error.")
(defconstant +close-unsupported-data+ 1003 "Unsupported data type.")
(defconstant +close-invalid-payload+ 1007 "Invalid payload data.")
(defconstant +close-policy-violation+ 1008 "Policy violation.")
(defconstant +close-message-too-big+ 1009 "Message too large.")
(defconstant +close-internal-error+ 1011 "Internal server error.")

;; Connection states
(defconstant +state-connecting+ :connecting "Handshake in progress.")
(defconstant +state-open+ :open "Connection open.")
(defconstant +state-closing+ :closing "Close handshake initiated.")
(defconstant +state-closed+ :closed "Connection closed.")

;;; ============================================================================
;;; Frame Structure
;;; ============================================================================

(defstruct (ws-frame
            (:constructor make-ws-frame
                (&key (fin t)
                      (rsv1 nil)
                      (rsv2 nil)
                      (rsv3 nil)
                      (opcode +opcode-text+)
                      (masked nil)
                      (payload-length 0)
                      (mask-key nil)
                      (payload nil))))
  "WebSocket frame per RFC 6455 Section 5.

   Frame Format:
     0                   1                   2                   3
     0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
    +-+-+-+-+-------+-+-------------+-------------------------------+
    |F|R|R|R| opcode|M| Payload len |    Extended payload length    |
    |I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
    |N|V|V|V|       |S|             |   (if payload len==126/127)   |
    | |1|2|3|       |K|             |                               |
    +-+-+-+-+-------+-+-------------+-------------------------------+"
  (fin t :type boolean)
  (rsv1 nil :type boolean)
  (rsv2 nil :type boolean)
  (rsv3 nil :type boolean)
  (opcode +opcode-text+ :type (unsigned-byte 4))
  (masked nil :type boolean)
  (payload-length 0 :type (integer 0 *))
  (mask-key nil :type (or null (simple-array (unsigned-byte 8) (4))))
  (payload nil :type (or null (simple-array (unsigned-byte 8) (*)))))

;;; ============================================================================
;;; Masking
;;; ============================================================================

(defun generate-mask-key ()
  "Generate a random 4-byte masking key.

   Per RFC 6455, client-to-server frames MUST be masked with a random key.

   Returns: 4-byte octet vector"
  (random-bytes 4))

(defun mask-payload (payload mask-key)
  "Apply masking to PAYLOAD using MASK-KEY.

   Per RFC 6455 Section 5.3:
   j = i MOD 4
   transformed-octet-i = original-octet-i XOR masking-key-octet-j

   Parameters:
     PAYLOAD - Octet vector (modified in place)
     MASK-KEY - 4-byte masking key

   Returns: PAYLOAD (modified)"
  (loop for i below (length payload)
        do (setf (aref payload i)
                 (logxor (aref payload i)
                         (aref mask-key (mod i 4)))))
  payload)

(defun unmask-payload (payload mask-key)
  "Remove masking from PAYLOAD.

   Masking is its own inverse (XOR), so this is identical to mask-payload.

   Parameters:
     PAYLOAD - Masked octet vector (modified in place)
     MASK-KEY - 4-byte masking key

   Returns: PAYLOAD (modified)"
  (mask-payload payload mask-key))

;;; ============================================================================
;;; Frame Encoding
;;; ============================================================================

(defun encode-frame (frame)
  "Encode a WebSocket frame to bytes.

   Parameters:
     FRAME - ws-frame structure

   Returns: Octet vector containing encoded frame"
  (let* ((fin (ws-frame-fin frame))
         (rsv1 (ws-frame-rsv1 frame))
         (rsv2 (ws-frame-rsv2 frame))
         (rsv3 (ws-frame-rsv3 frame))
         (opcode (ws-frame-opcode frame))
         (masked (ws-frame-masked frame))
         (payload-length (ws-frame-payload-length frame))
         (payload (ws-frame-payload frame))
         (mask-key (when masked (or (ws-frame-mask-key frame)
                                    (generate-mask-key)))))

    (let* ((header-size 2)
           (extended-length-size (cond
                                   ((< payload-length 126) 0)
                                   ((< payload-length 65536) 2)
                                   (t 8)))
           (mask-size (if masked 4 0))
           (total-size (+ header-size extended-length-size mask-size payload-length))
           (result (make-array total-size :element-type '(unsigned-byte 8)))
           (pos 0))

      ;; Byte 1: FIN, RSV1-3, Opcode
      (setf (aref result pos)
            (logior (if fin #x80 0)
                    (if rsv1 #x40 0)
                    (if rsv2 #x20 0)
                    (if rsv3 #x10 0)
                    (logand opcode #x0F)))
      (incf pos)

      ;; Byte 2: MASK, Payload length (7 bits)
      (let ((length-byte (cond
                           ((< payload-length 126) payload-length)
                           ((< payload-length 65536) 126)
                           (t 127))))
        (setf (aref result pos)
              (logior (if masked #x80 0)
                      length-byte))
        (incf pos))

      ;; Extended payload length (if needed)
      (cond
        ((< payload-length 126)
         nil)
        ((< payload-length 65536)
         ;; 16-bit length (network byte order)
         (setf (aref result pos) (logand (ash payload-length -8) #xFF))
         (incf pos)
         (setf (aref result pos) (logand payload-length #xFF))
         (incf pos))
        (t
         ;; 64-bit length (network byte order)
         (loop for shift from 56 downto 0 by 8
               do (setf (aref result pos) (logand (ash payload-length (- shift)) #xFF))
                  (incf pos))))

      ;; Masking key (if masked)
      (when masked
        (loop for i from 0 below 4
              do (setf (aref result pos) (aref mask-key i))
                 (incf pos)))

      ;; Payload (masked if required)
      (when (and payload (> payload-length 0))
        (if masked
            (loop for i from 0 below payload-length
                  do (setf (aref result pos)
                           (logxor (aref payload i)
                                   (aref mask-key (mod i 4))))
                     (incf pos))
            (replace result payload :start1 pos)))

      result)))

(defun encode-text-frame (text &key (fin t) (mask t))
  "Encode a text message as a WebSocket frame.

   Parameters:
     TEXT - Text string to encode
     FIN - Final fragment flag (default T)
     MASK - Whether to mask the payload (default T for client)

   Returns: Encoded frame as octet vector"
  (let* ((payload (string-to-octets text))
         (frame (make-ws-frame
                 :fin fin
                 :opcode +opcode-text+
                 :masked mask
                 :payload-length (length payload)
                 :payload payload
                 :mask-key (when mask (generate-mask-key)))))
    (encode-frame frame)))

(defun encode-binary-frame (data &key (fin t) (mask t))
  "Encode binary data as a WebSocket frame.

   Parameters:
     DATA - Octet vector to encode
     FIN - Final fragment flag (default T)
     MASK - Whether to mask the payload (default T)

   Returns: Encoded frame as octet vector"
  (let ((frame (make-ws-frame
                :fin fin
                :opcode +opcode-binary+
                :masked mask
                :payload-length (length data)
                :payload data
                :mask-key (when mask (generate-mask-key)))))
    (encode-frame frame)))

(defun encode-close-frame (code &optional reason)
  "Encode a close control frame.

   Parameters:
     CODE - Close code (see +close-* constants)
     REASON - Optional close reason string

   Returns: Encoded frame as octet vector"
  (let* ((reason-bytes (when reason (string-to-octets reason)))
         (payload-length (+ 2 (if reason-bytes (min (length reason-bytes) 123) 0)))
         (payload (make-array payload-length :element-type '(unsigned-byte 8))))
    ;; Close code (big-endian)
    (setf (aref payload 0) (logand (ash code -8) #xFF))
    (setf (aref payload 1) (logand code #xFF))
    ;; Reason (if present, max 123 bytes)
    (when reason-bytes
      (replace payload reason-bytes :start1 2
               :end2 (min (length reason-bytes) 123)))
    (let ((frame (make-ws-frame
                  :fin t
                  :opcode +opcode-close+
                  :masked t
                  :payload-length payload-length
                  :payload payload
                  :mask-key (generate-mask-key))))
      (encode-frame frame))))

(defun encode-ping-frame (&optional payload)
  "Encode a ping control frame.

   Parameters:
     PAYLOAD - Optional payload (max 125 bytes)

   Returns: Encoded frame as octet vector"
  (let* ((payload-data (cond
                         ((null payload)
                          (make-array 0 :element-type '(unsigned-byte 8)))
                         ((stringp payload)
                          (string-to-octets payload))
                         (t payload)))
         (payload-length (min (length payload-data) 125))
         (frame (make-ws-frame
                 :fin t
                 :opcode +opcode-ping+
                 :masked t
                 :payload-length payload-length
                 :payload (if (> (length payload-data) 125)
                              (subseq payload-data 0 125)
                              payload-data)
                 :mask-key (generate-mask-key))))
    (encode-frame frame)))

(defun encode-pong-frame (payload)
  "Encode a pong control frame.

   Parameters:
     PAYLOAD - Payload (should match received ping payload)

   Returns: Encoded frame as octet vector"
  (let* ((payload-length (if payload (min (length payload) 125) 0))
         (frame (make-ws-frame
                 :fin t
                 :opcode +opcode-pong+
                 :masked t
                 :payload-length payload-length
                 :payload (when payload
                            (if (> (length payload) 125)
                                (subseq payload 0 125)
                                payload))
                 :mask-key (generate-mask-key))))
    (encode-frame frame)))

;;; ============================================================================
;;; Frame Decoding
;;; ============================================================================

(defun decode-frame (data &key (start 0))
  "Decode a WebSocket frame from bytes.

   Parameters:
     DATA - Octet vector containing frame data
     START - Starting offset in data

   Returns: (values ws-frame bytes-consumed) or (values nil 0) if incomplete"
  (let ((available (- (length data) start)))
    ;; Need at least 2 bytes for basic header
    (when (< available 2)
      (return-from decode-frame (values nil 0)))

    (let* ((byte1 (aref data start))
           (byte2 (aref data (+ start 1)))
           ;; Parse byte 1
           (fin (not (zerop (logand byte1 #x80))))
           (rsv1 (not (zerop (logand byte1 #x40))))
           (rsv2 (not (zerop (logand byte1 #x20))))
           (rsv3 (not (zerop (logand byte1 #x10))))
           (opcode (logand byte1 #x0F))
           ;; Parse byte 2
           (masked (not (zerop (logand byte2 #x80))))
           (payload-len-7 (logand byte2 #x7F))
           (pos (+ start 2)))

      ;; Determine actual payload length
      (let ((payload-length
              (cond
                ((< payload-len-7 126)
                 payload-len-7)
                ((= payload-len-7 126)
                 (when (< available 4)
                   (return-from decode-frame (values nil 0)))
                 (prog1
                     (+ (ash (aref data pos) 8)
                        (aref data (+ pos 1)))
                   (incf pos 2)))
                (t ; 127
                 (when (< available 10)
                   (return-from decode-frame (values nil 0)))
                 (let ((length 0))
                   (loop for i from 0 below 8
                         do (setf length (+ (ash length 8)
                                            (aref data (+ pos i)))))
                   (incf pos 8)
                   length)))))

        ;; Check we have enough data for mask and payload
        (let* ((mask-size (if masked 4 0))
               (needed (+ (- pos start) mask-size payload-length)))
          (when (< available needed)
            (return-from decode-frame (values nil 0)))

          ;; Extract mask key if present
          (let ((mask-key nil))
            (when masked
              (setf mask-key (make-array 4 :element-type '(unsigned-byte 8)))
              (loop for i from 0 below 4
                    do (setf (aref mask-key i) (aref data pos))
                       (incf pos)))

            ;; Extract and unmask payload
            (let ((payload (make-array payload-length
                                       :element-type '(unsigned-byte 8))))
              (loop for i from 0 below payload-length
                    do (setf (aref payload i)
                             (if masked
                                 (logxor (aref data pos)
                                         (aref mask-key (mod i 4)))
                                 (aref data pos)))
                       (incf pos))

              ;; Return frame and bytes consumed
              (values (make-ws-frame
                       :fin fin
                       :rsv1 rsv1
                       :rsv2 rsv2
                       :rsv3 rsv3
                       :opcode opcode
                       :masked masked
                       :payload-length payload-length
                       :mask-key mask-key
                       :payload payload)
                      (- pos start)))))))))

;;; ============================================================================
;;; Frame Utilities
;;; ============================================================================

(defun control-frame-p (opcode)
  "Check if OPCODE is a control frame (close, ping, pong)."
  (>= opcode #x8))

(defun data-frame-p (opcode)
  "Check if OPCODE is a data frame (continuation, text, binary)."
  (< opcode #x8))

;;; End of frame.lisp
