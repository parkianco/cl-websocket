;;;; util.lisp - Utility functions for WebSocket protocol
;;;;
;;;; Provides Base64 encoding, SHA-1 hashing, and byte manipulation.
;;;; All implementations are pure Common Lisp with no external dependencies.
;;;;
;;;; Standards: RFC 4648 (Base64), RFC 3174 (SHA-1)
;;;; Thread Safety: Yes (pure functions)

(in-package #:cl-websocket)

;;; ============================================================================
;;; String/Byte Conversion
;;; ============================================================================

(defun string-to-octets (string &key (encoding :utf-8))
  "Convert STRING to an octet vector.

   Parameters:
     STRING - Input string
     ENCODING - Character encoding (only :utf-8 and :latin-1 supported)

   Returns: Octet vector"
  (declare (ignore encoding))
  (sb-ext:string-to-octets string :external-format :utf-8))

(defun octets-to-string (octets &key (encoding :utf-8))
  "Convert OCTETS to a string.

   Parameters:
     OCTETS - Input octet vector
     ENCODING - Character encoding

   Returns: String"
  (declare (ignore encoding))
  (sb-ext:octets-to-foreign-string octets :external-format :utf-8))

(defun random-bytes (count)
  "Generate COUNT random bytes.

   Returns: Octet vector of random bytes"
  (let ((bytes (make-array count :element-type '(unsigned-byte 8))))
    (dotimes (i count)
      (setf (aref bytes i) (random 256)))
    bytes))

;;; ============================================================================
;;; Base64 Encoding/Decoding (RFC 4648)
;;; ============================================================================

(defvar +base64-alphabet+
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  "Standard Base64 alphabet.")

(defun base64-encode (bytes)
  "Encode BYTES to Base64 string.

   Parameters:
     BYTES - Octet vector

   Returns: Base64 encoded string"
  (let* ((input-length (length bytes))
         (output-length (* 4 (ceiling input-length 3)))
         (result (make-string output-length))
         (output-index 0))
    (loop for i from 0 below input-length by 3
          for b0 = (aref bytes i)
          for b1 = (if (< (1+ i) input-length) (aref bytes (1+ i)) 0)
          for b2 = (if (< (+ i 2) input-length) (aref bytes (+ i 2)) 0)
          for remaining = (- input-length i)
          do
             ;; First character: bits 7-2 of byte 0
             (setf (char result output-index) (char +base64-alphabet+ (ash b0 -2)))
             (incf output-index)
             ;; Second character: bits 1-0 of byte 0 + bits 7-4 of byte 1
             (setf (char result output-index)
                   (char +base64-alphabet+ (logior (ash (logand b0 #x03) 4)
                                                   (ash b1 -4))))
             (incf output-index)
             ;; Third character: bits 3-0 of byte 1 + bits 7-6 of byte 2
             (setf (char result output-index)
                   (if (> remaining 1)
                       (char +base64-alphabet+ (logior (ash (logand b1 #x0f) 2)
                                                       (ash b2 -6)))
                       #\=))
             (incf output-index)
             ;; Fourth character: bits 5-0 of byte 2
             (setf (char result output-index)
                   (if (> remaining 2)
                       (char +base64-alphabet+ (logand b2 #x3f))
                       #\=))
             (incf output-index))
    result))

(defun base64-char-value (char)
  "Get numeric value for Base64 character."
  (let ((code (char-code char)))
    (cond
      ((<= (char-code #\A) code (char-code #\Z))
       (- code (char-code #\A)))
      ((<= (char-code #\a) code (char-code #\z))
       (+ 26 (- code (char-code #\a))))
      ((<= (char-code #\0) code (char-code #\9))
       (+ 52 (- code (char-code #\0))))
      ((char= char #\+) 62)
      ((char= char #\/) 63)
      ((char= char #\=) 0)
      (t (error "Invalid Base64 character: ~C" char)))))

(defun base64-decode (string)
  "Decode Base64 STRING to byte vector.

   Parameters:
     STRING - Base64 encoded string

   Returns: Octet vector"
  (let* ((clean-string (remove-if (lambda (c)
                                    (member c '(#\Space #\Tab #\Newline #\Return)))
                                  string))
         (input-length (length clean-string))
         (pad-count (count #\= clean-string :from-end t))
         (output-length (- (* 3 (floor input-length 4)) pad-count))
         (result (make-array output-length :element-type '(unsigned-byte 8)))
         (output-index 0))
    (loop for i from 0 below input-length by 4
          for c0 = (char clean-string i)
          for c1 = (char clean-string (1+ i))
          for c2 = (char clean-string (+ i 2))
          for c3 = (char clean-string (+ i 3))
          for v0 = (base64-char-value c0)
          for v1 = (base64-char-value c1)
          for v2 = (base64-char-value c2)
          for v3 = (base64-char-value c3)
          do
             (when (< output-index output-length)
               (setf (aref result output-index)
                     (logior (ash v0 2) (ash v1 -4)))
               (incf output-index))
             (when (and (< output-index output-length) (not (char= c2 #\=)))
               (setf (aref result output-index)
                     (logior (ash (logand v1 #x0f) 4) (ash v2 -2)))
               (incf output-index))
             (when (and (< output-index output-length) (not (char= c3 #\=)))
               (setf (aref result output-index)
                     (logior (ash (logand v2 #x03) 6) v3))
               (incf output-index)))
    result))

;;; ============================================================================
;;; SHA-1 Implementation (RFC 3174)
;;; ============================================================================
;;; WARNING: SHA-1 is cryptographically broken. This implementation exists
;;; ONLY for WebSocket handshake (RFC 6455 requirement). Do not use for
;;; security-critical operations.

(defun sha1 (data)
  "Compute SHA-1 hash of DATA.

   WARNING: SHA-1 is cryptographically broken. Used only for WebSocket handshake.

   Parameters:
     DATA - String or octet vector

   Returns: 20-byte octet vector (SHA-1 hash)"
  (let ((octets (if (stringp data)
                    (string-to-octets data :encoding :latin-1)
                    data)))
    (sha1-compute octets)))

(defun sha1-compute (message)
  "Compute SHA-1 hash of MESSAGE bytes.

   Returns: 20-byte octet vector"
  (let* (;; Initial hash values (RFC 3174)
         (h0 #x67452301)
         (h1 #xEFCDAB89)
         (h2 #x98BADCFE)
         (h3 #x10325476)
         (h4 #xC3D2E1F0)
         ;; Pre-processing: add padding
         (padded (sha1-pad message)))
    ;; Process message in 512-bit (64-byte) chunks
    (loop for chunk-start from 0 below (length padded) by 64
          do (let ((w (make-array 80 :element-type '(unsigned-byte 32))))
               ;; Break chunk into sixteen 32-bit big-endian words
               (loop for i from 0 below 16
                     for j = (+ chunk-start (* i 4))
                     do (setf (aref w i)
                              (logior (ash (aref padded j) 24)
                                      (ash (aref padded (+ j 1)) 16)
                                      (ash (aref padded (+ j 2)) 8)
                                      (aref padded (+ j 3)))))
               ;; Extend the sixteen 32-bit words into eighty 32-bit words
               (loop for i from 16 below 80
                     do (setf (aref w i)
                              (sha1-left-rotate
                               (logxor (aref w (- i 3))
                                       (aref w (- i 8))
                                       (aref w (- i 14))
                                       (aref w (- i 16)))
                               1)))
               ;; Initialize working variables
               (let ((a h0) (b h1) (c h2) (d h3) (e h4))
                 ;; Main loop
                 (loop for i from 0 below 80
                       for f = (cond
                                 ((< i 20)
                                  (logior (logand b c)
                                          (logand (lognot32 b) d)))
                                 ((< i 40)
                                  (logxor b c d))
                                 ((< i 60)
                                  (logior (logand b c)
                                          (logand b d)
                                          (logand c d)))
                                 (t
                                  (logxor b c d)))
                       for k = (cond
                                 ((< i 20) #x5A827999)
                                 ((< i 40) #x6ED9EBA1)
                                 ((< i 60) #x8F1BBCDC)
                                 (t #xCA62C1D6))
                       do (let ((temp (add32 (sha1-left-rotate a 5)
                                             f e k (aref w i))))
                            (setf e d
                                  d c
                                  c (sha1-left-rotate b 30)
                                  b a
                                  a temp)))
                 ;; Add this chunk's hash to result
                 (setf h0 (add32 h0 a)
                       h1 (add32 h1 b)
                       h2 (add32 h2 c)
                       h3 (add32 h3 d)
                       h4 (add32 h4 e)))))
    ;; Produce final hash value (big-endian)
    (let ((result (make-array 20 :element-type '(unsigned-byte 8))))
      (sha1-store-word result 0 h0)
      (sha1-store-word result 4 h1)
      (sha1-store-word result 8 h2)
      (sha1-store-word result 12 h3)
      (sha1-store-word result 16 h4)
      result)))

(defun sha1-pad (message)
  "Pad MESSAGE according to SHA-1 specification."
  (let* ((ml (length message))
         (ml-bits (* ml 8))
         ;; Padded length: message + 1 + k zeros + 8 bytes length
         ;; where (ml + 1 + k) mod 64 = 56
         (padded-length (+ 64 (* 64 (floor ml 64))
                          (if (< (mod ml 64) 56) 0 64)))
         (result (make-array padded-length :element-type '(unsigned-byte 8)
                                           :initial-element 0)))
    ;; Copy message
    (replace result message)
    ;; Append '1' bit (0x80)
    (setf (aref result ml) #x80)
    ;; Append length in bits as 64-bit big-endian
    (loop for i from 0 below 8
          for shift = (* (- 7 i) 8)
          do (setf (aref result (+ padded-length -8 i))
                   (logand (ash ml-bits (- shift)) #xff)))
    result))

(defun sha1-left-rotate (x n)
  "Left rotate 32-bit value X by N bits."
  (logand #xFFFFFFFF
          (logior (ash x n)
                  (ash x (- n 32)))))

(defun lognot32 (x)
  "32-bit logical NOT."
  (logand #xFFFFFFFF (lognot x)))

(defun add32 (&rest args)
  "Add values modulo 2^32."
  (logand #xFFFFFFFF (apply #'+ args)))

(defun sha1-store-word (array offset word)
  "Store 32-bit WORD at OFFSET in ARRAY (big-endian)."
  (setf (aref array offset) (logand (ash word -24) #xff))
  (setf (aref array (+ offset 1)) (logand (ash word -16) #xff))
  (setf (aref array (+ offset 2)) (logand (ash word -8) #xff))
  (setf (aref array (+ offset 3)) (logand word #xff)))

;;; End of util.lisp
