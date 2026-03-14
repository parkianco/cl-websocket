;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;; SPDX-License-Identifier: BSD-3-Clause

(defpackage :cl-websocket.test
  (:use :cl :cl-websocket)
  (:export :run-tests))

(in-package :cl-websocket.test)

(defmacro check (condition format-string &rest args)
  `(unless ,condition
     (error ,format-string ,@args)))

(defun octets-to-string (octets)
  (coerce (map 'list #'code-char octets) 'string))

(defun run-tests ()
  "Run the websocket frame codec regression suite."
  (let* ((frame (make-text-frame "Hi"))
         (encoded (encode-frame frame))
         (decoded (decode-frame encoded)))
    (check (websocket-frame-fin-p decoded) "Expected decoded frame to be final")
    (check (= 1 (websocket-frame-opcode decoded)) "Expected text opcode")
    (check (string= "Hi" (octets-to-string (websocket-frame-payload decoded)))
           "Expected text payload round-trip"))
  (let* ((frame (make-text-frame "mask" :masked-p t :masking-key #(1 2 3 4)))
         (decoded (decode-frame (encode-frame frame))))
    (check (websocket-frame-masked-p decoded) "Expected masked frame flag")
    (check (string= "mask" (octets-to-string (websocket-frame-payload decoded)))
           "Expected masked payload round-trip"))
  (check (equalp #(0 0 0 0) (mask-payload #(1 2 3 4) #(1 2 3 4)))
         "Expected XOR mask to zero identical octets")
  t)
