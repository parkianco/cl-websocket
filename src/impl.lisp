;;;; Copyright (C) 2025 Park Ian Co
;;;; License: MIT
;;;;
;;;; Implementation for CL_WEBSOCKET

(defun websocket-handshake (key)
  "Generate WebSocket handshake response."
  (concatenate 'string key "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))

(defun websocket-frame (opcode data)
  "Create WebSocket frame."
  (declare (ignore opcode data))
  (make-array 0))

(defun websocket-parse-frame (frame)
  "Parse WebSocket frame."
  (declare (ignore frame))
  (list :opcode 1 :data ""))

