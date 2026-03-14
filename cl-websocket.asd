(defsystem "CL_WEBSOCKET"
  :name "CL_WEBSOCKET"
  :version "0.1.0"
  :author "Park Ian Co"
  :license "MIT"
  :description "Websocket"
  :depends-on ()
  :components ((:module "src"
                :components ((:file "package")
                             (:file "impl" :depends-on ("package"))))
               (:module "test"
                :components ((:file "test"))))
  :in-order-to ((test-op (test-op "CL_WEBSOCKET/test")))
  :defsystem-depends-on ("prove")
  :perform (test-op (op c) (symbol-call :prove 'run c)))

(defsystem "CL_WEBSOCKET/test"
  :name "CL_WEBSOCKET/test"
  :depends-on ("CL_WEBSOCKET" "prove")
  :components ((:module "test"
                :components ((:file "test")))))
