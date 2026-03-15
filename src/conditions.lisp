;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;; SPDX-License-Identifier: Apache-2.0

(in-package #:cl-websocket)

(define-condition cl-websocket-error (error)
  ((message :initarg :message :reader cl-websocket-error-message))
  (:report (lambda (condition stream)
             (format stream "cl-websocket error: ~A" (cl-websocket-error-message condition))))
  (:documentation "Base error condition for the cl-websocket library."))

(define-condition cl-websocket-validation-error (cl-websocket-error)
  ()
  (:documentation "Signaled when a validation check fails in cl-websocket."))
