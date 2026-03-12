;;;; cl-websocket.asd - WebSocket Protocol Library
;;;;
;;;; RFC 6455 compliant WebSocket implementation in pure Common Lisp.
;;;; Uses only SBCL built-ins (sb-bsd-sockets, sb-thread) - no external dependencies.

(asdf:defsystem #:cl-websocket
  :name "cl-websocket"
  :description "RFC 6455 WebSocket Protocol Library - Pure Common Lisp"
  :version "1.0.0"
  :author "Parkian Company LLC"
  :license "MIT"
  :depends-on ()
  :serial t
  :components
  ((:file "package")
   (:module "src"
    :serial t
    :components
    ((:file "util")
     (:file "frame")
     (:file "handshake")
     (:file "connection")
     (:file "client"))))
  :in-order-to ((test-op (test-op #:cl-websocket/test))))

(asdf:defsystem #:cl-websocket/test
  :name "cl-websocket/test"
  :description "Tests for cl-websocket"
  :depends-on (#:cl-websocket)
  :serial t
  :components
  ((:module "test"
    :components
    ((:file "test-websocket"))))
  :perform (test-op (o c)
             (let ((result (symbol-call :cl-websocket.test :run-tests)))
               (unless result
                 (error "Tests failed")))))
