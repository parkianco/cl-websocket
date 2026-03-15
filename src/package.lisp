;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;; SPDX-License-Identifier: Apache-2.0

;;;; Copyright (C) 2025 Park Ian Co
;;;; License: MIT
;;;;
;;;; Package definition for CL_WEBSOCKET

(in-package :cl-user)

(defpackage :cl-websocket
  (:nicknames :websocket)
  (:use :cl)
  (:export
   #:websocket-frame
   #:websocket-frame-p
   #:make-websocket-frame
   #:websocket-frame-fin-p
   #:websocket-frame-opcode
   #:websocket-frame-masked-p
   #:websocket-frame-masking-key
   #:websocket-frame-payload
   #:make-text-frame
   #:encode-frame
   #:decode-frame
   #:mask-payload
   #:unmask-payload))

(in-package :cl-websocket)
