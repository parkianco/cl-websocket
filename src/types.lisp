;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;; SPDX-License-Identifier: Apache-2.0

(in-package #:cl-websocket)

;;; Core types for cl-websocket
(deftype cl-websocket-id () '(unsigned-byte 64))
(deftype cl-websocket-status () '(member :ready :active :error :shutdown))
