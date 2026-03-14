;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;; SPDX-License-Identifier: BSD-3-Clause

(in-package :cl-websocket)

(defstruct websocket-frame
  (fin-p t :type boolean)
  (opcode 1 :type (integer 0 15))
  (masked-p nil :type boolean)
  (masking-key #(0 0 0 0) :type (simple-array (unsigned-byte 8) (4)))
  (payload #() :type (simple-array (unsigned-byte 8) (*))))

(defun normalize-octets (data)
  "Coerce DATA to an octet vector."
  (cond
    ((typep data '(simple-array (unsigned-byte 8) (*))) data)
    ((stringp data)
     (map '(vector (unsigned-byte 8)) #'char-code data))
    ((vectorp data)
     (let ((result (make-array (length data) :element-type '(unsigned-byte 8))))
       (dotimes (index (length data) result)
         (let ((value (aref data index)))
           (unless (typep value '(unsigned-byte 8))
             (error "Non-octet payload element at ~D: ~S" index value))
           (setf (aref result index) value)))))
    ((listp data)
     (normalize-octets (coerce data 'vector)))
    (t
     (error "Unsupported websocket payload: ~S" data))))

(defun make-mask-key (masking-key)
  "Normalize MASKING-KEY to a 4-byte octet vector."
  (let ((octets (normalize-octets masking-key)))
    (unless (= 4 (length octets))
      (error "Masking key must contain exactly 4 octets"))
    octets))

(defun make-text-frame (text &key (masked-p nil) (masking-key #(0 0 0 0)) (fin-p t))
  "Create a text frame from TEXT."
  (make-websocket-frame
   :fin-p fin-p
   :opcode 1
   :masked-p masked-p
   :masking-key (make-mask-key masking-key)
   :payload (normalize-octets text)))

(defun mask-payload (payload masking-key)
  "Apply RFC 6455 masking to PAYLOAD with MASKING-KEY."
  (let* ((octets (normalize-octets payload))
         (key (make-mask-key masking-key))
         (result (make-array (length octets) :element-type '(unsigned-byte 8))))
    (dotimes (index (length octets) result)
      (setf (aref result index)
            (logxor (aref octets index)
                    (aref key (mod index 4)))))))

(defun unmask-payload (payload masking-key)
  "Unmask PAYLOAD with MASKING-KEY."
  (mask-payload payload masking-key))

(defun encode-extended-length (length)
  "Encode websocket payload LENGTH bytes."
  (cond
    ((< length 126)
     (values length #()))
    ((< length 65536)
     (values 126
             (vector (ldb (byte 8 8) length)
                     (ldb (byte 8 0) length))))
    (t
     (let ((result (make-array 8 :element-type '(unsigned-byte 8))))
       (dotimes (index 8 result)
         (setf (aref result (- 7 index))
               (ldb (byte 8 (* index 8)) length)))
       (values 127 result)))))

(defun encode-frame (frame)
  "Encode FRAME into an RFC 6455 websocket frame."
  (let* ((payload (normalize-octets (websocket-frame-payload frame)))
         (masked-p (websocket-frame-masked-p frame))
         (masking-key (make-mask-key (websocket-frame-masking-key frame)))
         (wire-payload (if masked-p
                           (mask-payload payload masking-key)
                           payload)))
    (multiple-value-bind (length-code extra-length)
        (encode-extended-length (length payload))
      (let* ((header-size (+ 2 (length extra-length) (if masked-p 4 0)))
             (result (make-array (+ header-size (length wire-payload))
                                 :element-type '(unsigned-byte 8)
                                 :initial-element 0)))
        (setf (aref result 0)
              (logior (if (websocket-frame-fin-p frame) #x80 0)
                      (logand (websocket-frame-opcode frame) #x0f)))
        (setf (aref result 1)
              (logior (if masked-p #x80 0) length-code))
        (replace result extra-length :start1 2)
        (when masked-p
          (replace result masking-key :start1 (+ 2 (length extra-length))))
        (replace result wire-payload
                 :start1 (+ 2 (length extra-length) (if masked-p 4 0)))
        result))))

(defun decode-extended-length (frame index length-code)
  "Decode websocket payload length starting at INDEX."
  (cond
    ((< length-code 126)
     (values length-code index))
    ((= length-code 126)
     (values (+ (ash (aref frame index) 8)
                (aref frame (1+ index)))
             (+ index 2)))
    (t
     (let ((length 0))
       (dotimes (offset 8)
         (setf length (+ (ash length 8)
                         (aref frame (+ index offset)))))
       (values length (+ index 8))))))

(defun decode-frame (data)
  "Decode DATA into a websocket-frame."
  (let* ((frame (normalize-octets data))
         (first-byte (aref frame 0))
         (second-byte (aref frame 1))
         (fin-p (logbitp 7 first-byte))
         (opcode (logand first-byte #x0f))
         (masked-p (logbitp 7 second-byte))
         (length-code (logand second-byte #x7f)))
    (multiple-value-bind (payload-length payload-index)
        (decode-extended-length frame 2 length-code)
      (let* ((masking-key (if masked-p
                              (subseq frame payload-index (+ payload-index 4))
                              #(0 0 0 0)))
             (payload-start (+ payload-index (if masked-p 4 0)))
             (payload-end (+ payload-start payload-length))
             (payload-bytes (subseq frame payload-start payload-end))
             (payload (if masked-p
                          (unmask-payload payload-bytes masking-key)
                          payload-bytes)))
        (make-websocket-frame
         :fin-p fin-p
         :opcode opcode
         :masked-p masked-p
         :masking-key (make-mask-key masking-key)
         :payload (normalize-octets payload))))))
