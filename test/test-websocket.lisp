;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;; SPDX-License-Identifier: BSD-3-Clause

;;;; test-websocket.lisp - Tests for cl-websocket library
;;;;
;;;; Test suite covering frame encoding/decoding, handshake, and utilities.
;;;; Run with: (asdf:test-system :cl-websocket)

(defpackage #:cl-websocket-test
  (:use #:cl #:cl-websocket)
  (:export #:run-tests))

(in-package #:cl-websocket-test)

;;; ============================================================================
;;; Test Framework
;;; ============================================================================

(defvar *test-count* 0)
(defvar *pass-count* 0)
(defvar *fail-count* 0)

(defmacro deftest (name &body body)
  "Define a test case."
  `(defun ,name ()
     (format t "~&Testing ~A... " ',name)
     (handler-case
         (progn ,@body
                (format t "PASS~%")
                (incf *pass-count*))
       (error (e)
         (format t "FAIL: ~A~%" e)
         (incf *fail-count*)))
     (incf *test-count*)))

(defmacro assert-equal (expected actual &optional message)
  "Assert that EXPECTED equals ACTUAL."
  `(unless (equal ,expected ,actual)
     (error "~@[~A: ~]Expected ~S but got ~S"
            ,message ,expected ,actual)))

(defmacro assert-true (expr &optional message)
  "Assert that EXPR is true."
  `(unless ,expr
     (error "~@[~A: ~]Expected true but got NIL" ,message)))

(defmacro assert-equalp (expected actual &optional message)
  "Assert that EXPECTED equalp ACTUAL (for arrays)."
  `(unless (equalp ,expected ,actual)
     (error "~@[~A: ~]Expected ~S but got ~S"
            ,message ,expected ,actual)))

;;; ============================================================================
;;; Base64 Tests
;;; ============================================================================

(deftest test-base64-encode-empty
  (assert-equal "" (cl-websocket::base64-encode #())))

(deftest test-base64-encode-single
  (assert-equal "TQ==" (cl-websocket::base64-encode #(77))))

(deftest test-base64-encode-two
  (assert-equal "TWE=" (cl-websocket::base64-encode #(77 97))))

(deftest test-base64-encode-three
  (assert-equal "TWFu" (cl-websocket::base64-encode #(77 97 110))))

(deftest test-base64-encode-hello
  (let ((hello (cl-websocket::string-to-octets "Hello")))
    (assert-equal "SGVsbG8=" (cl-websocket::base64-encode hello))))

(deftest test-base64-roundtrip
  (let* ((original "The quick brown fox jumps over the lazy dog")
         (octets (cl-websocket::string-to-octets original))
         (encoded (cl-websocket::base64-encode octets))
         (decoded (cl-websocket::base64-decode encoded)))
    (assert-equalp octets decoded)))

;;; ============================================================================
;;; SHA-1 Tests (RFC 3174 test vectors)
;;; ============================================================================

(deftest test-sha1-empty
  (let ((hash (cl-websocket::sha1 "")))
    (assert-equal 20 (length hash))
    ;; SHA1("") = da39a3ee5e6b4b0d3255bfef95601890afd80709
    (assert-equal #xda (aref hash 0))
    (assert-equal #x39 (aref hash 1))))

(deftest test-sha1-abc
  (let ((hash (cl-websocket::sha1 "abc")))
    ;; SHA1("abc") = a9993e364706816aba3e25717850c26c9cd0d89d
    (assert-equal #xa9 (aref hash 0))
    (assert-equal #x99 (aref hash 1))
    (assert-equal #x3e (aref hash 2))))

(deftest test-sha1-websocket-key
  ;; Test with the RFC 6455 example
  (let* ((key "dGhlIHNhbXBsZSBub25jZQ==")
         (guid "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
         (combined (concatenate 'string key guid))
         (hash (cl-websocket::sha1 combined))
         (encoded (cl-websocket::base64-encode hash)))
    (assert-equal "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" encoded)))

;;; ============================================================================
;;; Frame Encoding Tests
;;; ============================================================================

(deftest test-frame-encode-unmasked-text
  (let* ((frame (make-ws-frame
                 :fin t
                 :opcode +opcode-text+
                 :masked nil
                 :payload-length 5
                 :payload (cl-websocket::string-to-octets "Hello")))
         (encoded (cl-websocket::encode-frame frame)))
    ;; FIN=1, opcode=1 => 0x81
    (assert-equal #x81 (aref encoded 0))
    ;; Masked=0, length=5 => 0x05
    (assert-equal #x05 (aref encoded 1))
    ;; Payload starts at byte 2
    (assert-equal 7 (length encoded))))

(deftest test-frame-encode-masked-text
  (let* ((frame (make-ws-frame
                 :fin t
                 :opcode +opcode-text+
                 :masked t
                 :payload-length 5
                 :payload (cl-websocket::string-to-octets "Hello")
                 :mask-key #(#x37 #xfa #x21 #x3d)))
         (encoded (cl-websocket::encode-frame frame)))
    ;; FIN=1, opcode=1 => 0x81
    (assert-equal #x81 (aref encoded 0))
    ;; Masked=1, length=5 => 0x85
    (assert-equal #x85 (aref encoded 1))
    ;; Mask key at bytes 2-5
    (assert-equal #x37 (aref encoded 2))
    ;; Total: 2 header + 4 mask + 5 payload = 11
    (assert-equal 11 (length encoded))))

(deftest test-frame-encode-extended-length-16bit
  (let* ((payload (make-array 200 :element-type '(unsigned-byte 8)
                                  :initial-element 65))
         (frame (make-ws-frame
                 :fin t
                 :opcode +opcode-binary+
                 :masked nil
                 :payload-length 200
                 :payload payload))
         (encoded (cl-websocket::encode-frame frame)))
    ;; Length byte should be 126 (indicating 16-bit extended length)
    (assert-equal 126 (logand (aref encoded 1) #x7f))
    ;; Extended length in bytes 2-3 (big-endian)
    (assert-equal 0 (aref encoded 2))
    (assert-equal 200 (aref encoded 3))))

(deftest test-frame-encode-ping
  (let ((encoded (encode-ping-frame nil)))
    ;; FIN=1, opcode=9 => 0x89
    (assert-equal #x89 (aref encoded 0))))

(deftest test-frame-encode-close
  (let ((encoded (encode-close-frame +close-normal+ "bye")))
    ;; FIN=1, opcode=8 => 0x88
    (assert-equal #x88 (aref encoded 0))))

;;; ============================================================================
;;; Frame Decoding Tests
;;; ============================================================================

(deftest test-frame-decode-simple
  (let* ((data #(#x81 #x05 #x48 #x65 #x6c #x6c #x6f))
         (frame (decode-frame data)))
    (assert-true (ws-frame-fin frame))
    (assert-equal +opcode-text+ (ws-frame-opcode frame))
    (assert-equal 5 (ws-frame-payload-length frame))))

(deftest test-frame-decode-masked
  ;; Masked "Hello" with mask key 0x37fa213d
  (let* ((data #(#x81 #x85 #x37 #xfa #x21 #x3d
                 #x7f #x9f #x4d #x51 #x58))
         (frame (decode-frame data)))
    (assert-true (ws-frame-fin frame))
    (assert-true (ws-frame-masked frame))
    (assert-equal 5 (ws-frame-payload-length frame))
    ;; Payload should be unmasked to "Hello"
    (assert-equal #x48 (aref (ws-frame-payload frame) 0))))

(deftest test-frame-roundtrip
  (let* ((original (make-ws-frame
                    :fin t
                    :opcode +opcode-text+
                    :masked nil
                    :payload-length 11
                    :payload (cl-websocket::string-to-octets "Hello World")))
         (encoded (cl-websocket::encode-frame original))
         (decoded (decode-frame encoded)))
    (assert-equal (ws-frame-fin original) (ws-frame-fin decoded))
    (assert-equal (ws-frame-opcode original) (ws-frame-opcode decoded))
    (assert-equal (ws-frame-payload-length original)
                  (ws-frame-payload-length decoded))
    (assert-equalp (ws-frame-payload original)
                   (ws-frame-payload decoded))))

;;; ============================================================================
;;; Masking Tests
;;; ============================================================================

(deftest test-masking-inverse
  (let* ((original #(#x48 #x65 #x6c #x6c #x6f))
         (copy (copy-seq original))
         (mask-key #(#x37 #xfa #x21 #x3d)))
    (cl-websocket::mask-payload copy mask-key)
    ;; Should be different after masking
    (assert-true (not (equalp original copy)))
    ;; Should be back to original after unmasking
    (cl-websocket::unmask-payload copy mask-key)
    (assert-equalp original copy)))

;;; ============================================================================
;;; Handshake Tests
;;; ============================================================================

(deftest test-generate-client-key
  (let ((key (cl-websocket::generate-client-key)))
    ;; Base64 encoded 16 bytes = 24 characters
    (assert-equal 24 (length key))))

(deftest test-compute-accept-key
  ;; RFC 6455 example
  (let ((accept (compute-accept-key "dGhlIHNhbXBsZSBub25jZQ==")))
    (assert-equal "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" accept)))

(deftest test-make-handshake-request
  (multiple-value-bind (request key)
      (cl-websocket::make-handshake-request "example.com" 80 "/ws")
    (assert-true (search "GET /ws HTTP/1.1" request))
    (assert-true (search "Host: example.com" request))
    (assert-true (search "Upgrade: websocket" request))
    (assert-true (search "Connection: Upgrade" request))
    (assert-true (search "Sec-WebSocket-Key:" request))
    (assert-true (search "Sec-WebSocket-Version: 13" request))
    (assert-equal 24 (length key))))

(deftest test-parse-handshake-response
  (let* ((response "HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=

")
         (parsed (cl-websocket::parse-handshake-response response)))
    (assert-equal 101 (getf parsed :status-code))
    (assert-true (gethash "Upgrade" (getf parsed :headers)))))

;;; ============================================================================
;;; Control Frame Tests
;;; ============================================================================

(deftest test-control-frame-p
  (assert-true (control-frame-p +opcode-close+))
  (assert-true (control-frame-p +opcode-ping+))
  (assert-true (control-frame-p +opcode-pong+))
  (assert-true (not (control-frame-p +opcode-text+)))
  (assert-true (not (control-frame-p +opcode-binary+))))

(deftest test-data-frame-p
  (assert-true (data-frame-p +opcode-continuation+))
  (assert-true (data-frame-p +opcode-text+))
  (assert-true (data-frame-p +opcode-binary+))
  (assert-true (not (data-frame-p +opcode-close+))))

;;; ============================================================================
;;; Test Runner
;;; ============================================================================

(defun run-tests ()
  "Run all tests and report results."
  (setf *test-count* 0
        *pass-count* 0
        *fail-count* 0)

  (format t "~&~%========================================~%")
  (format t "Running cl-websocket tests~%")
  (format t "========================================~%~%")

  ;; Base64 tests
  (test-base64-encode-empty)
  (test-base64-encode-single)
  (test-base64-encode-two)
  (test-base64-encode-three)
  (test-base64-encode-hello)
  (test-base64-roundtrip)

  ;; SHA-1 tests
  (test-sha1-empty)
  (test-sha1-abc)
  (test-sha1-websocket-key)

  ;; Frame encoding tests
  (test-frame-encode-unmasked-text)
  (test-frame-encode-masked-text)
  (test-frame-encode-extended-length-16bit)
  (test-frame-encode-ping)
  (test-frame-encode-close)

  ;; Frame decoding tests
  (test-frame-decode-simple)
  (test-frame-decode-masked)
  (test-frame-roundtrip)

  ;; Masking tests
  (test-masking-inverse)

  ;; Handshake tests
  (test-generate-client-key)
  (test-compute-accept-key)
  (test-make-handshake-request)
  (test-parse-handshake-response)

  ;; Control frame tests
  (test-control-frame-p)
  (test-data-frame-p)

  (format t "~%========================================~%")
  (format t "Results: ~D/~D passed (~D failed)~%"
          *pass-count* *test-count* *fail-count*)
  (format t "========================================~%")

  (zerop *fail-count*))

;;; End of test-websocket.lisp
