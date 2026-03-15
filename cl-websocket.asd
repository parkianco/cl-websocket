(asdf:defsystem #:cl-websocket
  :name "cl-websocket"
  :version "0.1.0"
  :author "Parkian Company LLC"
  :license "Apache-2.0"
  :description "Minimal RFC 6455 frame encoding and decoding utilities"
  :serial t
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "impl"))))
  :in-order-to ((asdf:test-op (asdf:test-op #:cl-websocket/test))))

(asdf:defsystem #:cl-websocket/test
  :name "cl-websocket/test"
  :depends-on (#:cl-websocket)
  :serial t
  :components ((:module "test"
                :serial t
                :components ((:file "test"))))
  :perform (asdf:test-op (op c)
             (declare (ignore op c))
             (unless (uiop:symbol-call :cl-websocket.test :run-tests)
               (error "Tests failed"))))
