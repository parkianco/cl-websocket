;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;; SPDX-License-Identifier: BSD-3-Clause

;;;; Copyright (C) 2025 Park Ian Co
;;;; License: MIT
;;;;
;;;; Tests for CL_WEBSOCKET

(in-package :CL_WEBSOCKET)

(import 'prove:run)

(plan 1)

(ok (stringp (hello)) "hello returns a string")

(finalize)
