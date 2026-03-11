;;;; client.lisp - WebSocket client implementation
;;;;
;;;; Provides high-level WebSocket client functionality including connection
;;;; establishment, message sending/receiving, and clean shutdown.
;;;;
;;;; Uses sb-bsd-sockets for network connectivity.
;;;;
;;;; Standards: RFC 6455 (WebSocket Protocol)
;;;; Thread Safety: Yes (connection operations are thread-safe)

(in-package #:cl-websocket)

;;; ============================================================================
;;; Client Connection
;;; ============================================================================

(defun connect (host port &key (path "/") protocols extensions origin)
  "Connect to a WebSocket server.

   Parameters:
     HOST - Server hostname or IP address
     PORT - Server port
     PATH - Request path (default \"/\")
     PROTOCOLS - List of subprotocol names to request
     EXTENSIONS - List of extension names to request
     ORIGIN - Origin header value

   Returns: ws-connection on success

   Signals:
     websocket-connection-error - If connection fails
     websocket-handshake-error - If handshake fails

   Example:
     (connect \"echo.websocket.org\" 80 :path \"/\")
     (connect \"localhost\" 8080 :path \"/ws\" :protocols '(\"chat\"))"

  ;; Create socket and connect
  (let* ((socket (make-instance 'sb-bsd-sockets:inet-socket
                                :type :stream :protocol :tcp))
         (address (resolve-host host)))
    (handler-case
        (sb-bsd-sockets:socket-connect socket address port)
      (error (e)
        (sb-bsd-sockets:socket-close socket)
        (error 'websocket-connection-error
               :message (format nil "Failed to connect to ~A:~D: ~A"
                                host port e))))

    ;; Create stream
    (let ((stream (sb-bsd-sockets:socket-make-stream
                   socket
                   :input t :output t
                   :element-type '(unsigned-byte 8)
                   :buffering :full)))

      ;; Create connection object
      (let ((connection (make-ws-connection :socket socket :stream stream)))

        ;; Perform handshake
        (handler-case
            (perform-handshake connection host port path
                               :protocols protocols
                               :extensions extensions
                               :origin origin)
          (error (e)
            (close-connection connection)
            (error e)))

        ;; Mark as open
        (set-connection-state connection +state-open+)

        connection))))

(defun resolve-host (host)
  "Resolve hostname to IP address.

   Returns: IP address as integer vector"
  (cond
    ;; Already an IP address
    ((and (stringp host)
          (every (lambda (c) (or (digit-char-p c) (char= c #\.))) host))
     (sb-bsd-sockets:make-inet-address host))
    ;; Resolve hostname
    (t
     (let ((host-ent (sb-bsd-sockets:get-host-by-name host)))
       (unless host-ent
         (error 'websocket-connection-error
                :message (format nil "Cannot resolve hostname: ~A" host)))
       (sb-bsd-sockets:host-ent-address host-ent)))))

(defun perform-handshake (connection host port path &key protocols extensions origin)
  "Perform WebSocket handshake on CONNECTION.

   Sends upgrade request and validates response."
  (let ((stream (ws-connection-stream connection)))
    ;; Generate and send handshake request
    (multiple-value-bind (request client-key)
        (make-handshake-request host port path
                                :protocols protocols
                                :extensions extensions
                                :origin origin)
      ;; Send request
      (write-sequence (string-to-octets request :encoding :latin-1) stream)
      (force-output stream)

      ;; Read response
      (let ((response-text (read-http-response stream)))
        ;; Parse and validate
        (let ((response (parse-handshake-response response-text)))
          (validate-handshake-response response client-key))))))

;;; ============================================================================
;;; Client Operations
;;; ============================================================================

(defun send-text (connection text)
  "Send a text message over CONNECTION.

   Parameters:
     CONNECTION - ws-connection instance
     TEXT - Text string to send

   Returns: T on success

   Signals:
     websocket-connection-error - If connection is not open"
  (unless (connection-open-p connection)
    (error 'websocket-connection-error
           :message "Connection is not open"))

  (let ((frame (encode-text-frame text :mask t)))
    (write-frame connection frame)
    t))

(defun send-binary (connection data)
  "Send binary data over CONNECTION.

   Parameters:
     CONNECTION - ws-connection instance
     DATA - Octet vector to send

   Returns: T on success"
  (unless (connection-open-p connection)
    (error 'websocket-connection-error
           :message "Connection is not open"))

  (let ((frame (encode-binary-frame data :mask t)))
    (write-frame connection frame)
    t))

(defun send-ping (connection &optional payload)
  "Send a ping frame over CONNECTION.

   Parameters:
     CONNECTION - ws-connection instance
     PAYLOAD - Optional payload (max 125 bytes)

   Returns: T on success"
  (unless (connection-open-p connection)
    (return-from send-ping nil))

  (let ((frame (encode-ping-frame payload)))
    (write-frame connection frame)
    t))

(defun receive (connection &key timeout)
  "Receive a message from CONNECTION.

   Blocks until a message is received or timeout expires.

   Parameters:
     CONNECTION - ws-connection instance
     TIMEOUT - Read timeout in seconds (optional)

   Returns: (values data type) where type is :text, :binary, or :close
            NIL on connection close or timeout"
  (unless (connection-open-p connection)
    (return-from receive nil))

  (receive-message connection :timeout timeout))

(defun close-connection (connection &key (code +close-normal+) reason)
  "Close a WebSocket connection gracefully.

   Sends close frame and closes underlying socket.

   Parameters:
     CONNECTION - ws-connection instance
     CODE - Close code (default 1000 normal)
     REASON - Optional close reason string

   Returns: T on success"
  (sb-thread:with-mutex ((ws-connection-lock connection))
    (unless (member (ws-connection-state connection)
                    (list +state-closing+ +state-closed+))
      ;; Send close frame
      (handler-case
          (let ((frame (encode-close-frame code reason)))
            (write-frame connection frame))
        (error () nil))

      (setf (ws-connection-state connection) +state-closing+)
      (setf (ws-connection-close-code connection) code)
      (setf (ws-connection-close-reason connection) reason))

    ;; Close stream and socket
    (when (ws-connection-stream connection)
      (handler-case
          (close (ws-connection-stream connection))
        (error () nil))
      (setf (ws-connection-stream connection) nil))

    (when (ws-connection-socket connection)
      (handler-case
          (sb-bsd-sockets:socket-close (ws-connection-socket connection))
        (error () nil))
      (setf (ws-connection-socket connection) nil))

    (setf (ws-connection-state connection) +state-closed+)
    t))

;;; ============================================================================
;;; Utility Functions
;;; ============================================================================

(defun with-websocket ((var host port &rest options) &body body)
  "Execute BODY with a WebSocket connection bound to VAR.

   Connection is automatically closed when BODY exits.

   Example:
     (with-websocket (ws \"echo.websocket.org\" 80)
       (send-text ws \"Hello\")
       (receive ws))"
  `(let ((,var (apply #'connect ,host ,port (list ,@options))))
     (unwind-protect
          (progn ,@body)
       (close-connection ,var))))

;;; End of client.lisp
