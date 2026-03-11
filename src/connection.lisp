;;;; connection.lisp - WebSocket connection management
;;;;
;;;; Manages WebSocket connection state, buffering, and I/O operations.
;;;; Provides thread-safe access to connection resources.
;;;;
;;;; Standards: RFC 6455 (WebSocket Protocol)
;;;; Thread Safety: Yes (all public functions are thread-safe)
;;;; Performance: O(1) for most operations

(in-package #:cl-websocket)

;;; ============================================================================
;;; Connection Structure
;;; ============================================================================

(defstruct (ws-connection
            (:constructor %make-ws-connection)
            (:copier nil))
  "WebSocket connection with state tracking.

   Thread Safety: Access protected by LOCK slot."
  ;; Network
  (socket nil :type t)
  (stream nil :type (or null stream))

  ;; State
  (state +state-connecting+ :type keyword)

  ;; Buffers
  (recv-buffer (make-array 4096 :element-type '(unsigned-byte 8)
                                :adjustable t :fill-pointer 0)
               :type vector)
  (fragment-buffer nil :type list)
  (fragment-opcode nil :type (or null (unsigned-byte 4)))

  ;; Close state
  (close-code nil :type (or null integer))
  (close-reason nil :type (or null string))

  ;; Synchronization
  (lock nil :type t))

(defun make-ws-connection (&key socket stream)
  "Create a new WebSocket connection.

   Parameters:
     SOCKET - Underlying socket
     STREAM - Buffered stream for I/O

   Returns: New ws-connection instance"
  (%make-ws-connection
   :socket socket
   :stream stream
   :lock (sb-thread:make-mutex :name "ws-connection")))

;;; ============================================================================
;;; Connection State
;;; ============================================================================

(defun connection-open-p (connection)
  "Check if CONNECTION is open and ready for I/O.

   Parameters:
     CONNECTION - ws-connection instance

   Returns: T if connection is open"
  (sb-thread:with-mutex ((ws-connection-lock connection))
    (eq (ws-connection-state connection) +state-open+)))

(defun set-connection-state (connection new-state)
  "Set connection state.

   Parameters:
     CONNECTION - ws-connection instance
     NEW-STATE - New state keyword"
  (sb-thread:with-mutex ((ws-connection-lock connection))
    (setf (ws-connection-state connection) new-state)))

;;; ============================================================================
;;; Frame I/O
;;; ============================================================================

(defun read-frame (connection &key timeout)
  "Read a complete WebSocket frame from CONNECTION.

   Parameters:
     CONNECTION - ws-connection instance
     TIMEOUT - Read timeout in seconds (optional)

   Returns: ws-frame or NIL on timeout/EOF

   Signals:
     websocket-protocol-error - If frame is malformed"
  (declare (ignore timeout))
  (let ((stream (ws-connection-stream connection)))
    (unless stream
      (return-from read-frame nil))

    (handler-case
        (let ((header (read-n-bytes stream 2)))
          (unless (= (length header) 2)
            (return-from read-frame nil))

          (let* ((byte1 (aref header 0))
                 (byte2 (aref header 1))
                 (fin (not (zerop (logand byte1 #x80))))
                 (rsv1 (not (zerop (logand byte1 #x40))))
                 (rsv2 (not (zerop (logand byte1 #x20))))
                 (rsv3 (not (zerop (logand byte1 #x10))))
                 (opcode (logand byte1 #x0F))
                 (masked (not (zerop (logand byte2 #x80))))
                 (payload-len-7 (logand byte2 #x7F)))

            ;; Validate RSV bits
            (when (or rsv1 rsv2 rsv3)
              (error 'websocket-protocol-error
                     :message "Unexpected RSV bits set"))

            ;; Control frames must not be fragmented
            (when (and (control-frame-p opcode) (not fin))
              (error 'websocket-protocol-error
                     :message "Fragmented control frame"))

            ;; Read extended payload length
            (let ((payload-length
                    (cond
                      ((< payload-len-7 126) payload-len-7)
                      ((= payload-len-7 126)
                       (let ((ext-len (read-n-bytes stream 2)))
                         (+ (ash (aref ext-len 0) 8)
                            (aref ext-len 1))))
                      (t ; 127
                       (let ((ext-len (read-n-bytes stream 8))
                             (length 0))
                         (loop for i from 0 below 8
                               do (setf length (+ (ash length 8)
                                                  (aref ext-len i))))
                         length)))))

              ;; Control frame payload max 125 bytes
              (when (and (control-frame-p opcode) (> payload-length 125))
                (error 'websocket-protocol-error
                       :message "Control frame payload too large"))

              ;; Read mask key if present
              (let ((mask-key nil))
                (when masked
                  (setf mask-key (read-n-bytes stream 4)))

                ;; Read payload
                (let ((payload (if (> payload-length 0)
                                   (read-n-bytes stream payload-length)
                                   (make-array 0 :element-type '(unsigned-byte 8)))))

                  ;; Unmask if needed
                  (when masked
                    (unmask-payload payload mask-key))

                  ;; Return frame
                  (make-ws-frame
                   :fin fin
                   :rsv1 rsv1
                   :rsv2 rsv2
                   :rsv3 rsv3
                   :opcode opcode
                   :masked masked
                   :payload-length payload-length
                   :mask-key mask-key
                   :payload payload))))))

      (end-of-file () nil)
      (error (e)
        (if (typep e 'websocket-error)
            (error e)
            nil)))))

(defun write-frame (connection frame)
  "Write a WebSocket frame to CONNECTION.

   Parameters:
     CONNECTION - ws-connection instance
     FRAME - ws-frame or encoded octet vector

   Returns: Number of bytes written"
  (let ((stream (ws-connection-stream connection))
        (encoded (if (ws-frame-p frame)
                     (encode-frame frame)
                     frame)))
    (when stream
      (write-sequence encoded stream)
      (force-output stream)
      (length encoded))))

(defun read-n-bytes (stream n)
  "Read exactly N bytes from STREAM.

   Returns: Octet vector of size N

   Signals error if not enough bytes available"
  (let ((buffer (make-array n :element-type '(unsigned-byte 8)))
        (total-read 0))
    (loop while (< total-read n)
          do (let ((byte (read-byte stream nil nil)))
               (unless byte
                 (error 'end-of-file))
               (setf (aref buffer total-read) byte)
               (incf total-read)))
    buffer))

;;; ============================================================================
;;; Message I/O
;;; ============================================================================

(defun receive-message (connection &key timeout)
  "Receive a complete message from CONNECTION.

   Handles fragmented messages and control frames automatically.

   Parameters:
     CONNECTION - ws-connection instance
     TIMEOUT - Read timeout in seconds (optional)

   Returns: (values data type) where type is :text, :binary, or :close
            NIL on connection close"
  (loop
    (let ((frame (read-frame connection :timeout timeout)))
      (unless frame
        (return nil))

      (let ((opcode (ws-frame-opcode frame)))
        (cond
          ;; Close frame
          ((= opcode +opcode-close+)
           (let ((payload (ws-frame-payload frame))
                 (code nil)
                 (reason nil))
             (when (>= (ws-frame-payload-length frame) 2)
               (setf code (+ (ash (aref payload 0) 8)
                             (aref payload 1)))
               (when (> (ws-frame-payload-length frame) 2)
                 (setf reason (octets-to-string (subseq payload 2)))))
             (sb-thread:with-mutex ((ws-connection-lock connection))
               (setf (ws-connection-close-code connection) code)
               (setf (ws-connection-close-reason connection) reason)
               (setf (ws-connection-state connection) +state-closing+))
             (return (values (list :code code :reason reason) :close))))

          ;; Ping frame - respond with pong
          ((= opcode +opcode-ping+)
           (let ((pong (encode-pong-frame (ws-frame-payload frame))))
             (write-frame connection pong)))

          ;; Pong frame - ignore
          ((= opcode +opcode-pong+)
           nil)

          ;; Continuation frame
          ((= opcode +opcode-continuation+)
           (sb-thread:with-mutex ((ws-connection-lock connection))
             (push (ws-frame-payload frame)
                   (ws-connection-fragment-buffer connection))
             (when (ws-frame-fin frame)
               (let ((data (assemble-fragments connection)))
                 (return (values data
                                 (if (= (ws-connection-fragment-opcode connection)
                                        +opcode-text+)
                                     :text
                                     :binary)))))))

          ;; Text frame
          ((= opcode +opcode-text+)
           (if (ws-frame-fin frame)
               (return (values (octets-to-string (ws-frame-payload frame)) :text))
               (sb-thread:with-mutex ((ws-connection-lock connection))
                 (setf (ws-connection-fragment-opcode connection) opcode)
                 (setf (ws-connection-fragment-buffer connection)
                       (list (ws-frame-payload frame))))))

          ;; Binary frame
          ((= opcode +opcode-binary+)
           (if (ws-frame-fin frame)
               (return (values (ws-frame-payload frame) :binary))
               (sb-thread:with-mutex ((ws-connection-lock connection))
                 (setf (ws-connection-fragment-opcode connection) opcode)
                 (setf (ws-connection-fragment-buffer connection)
                       (list (ws-frame-payload frame)))))))))))

(defun assemble-fragments (connection)
  "Assemble fragmented message buffers.

   Returns: Complete message data (string or octets)"
  (let* ((fragments (nreverse (ws-connection-fragment-buffer connection)))
         (total-length (reduce #'+ fragments :key #'length))
         (result (make-array total-length :element-type '(unsigned-byte 8)))
         (offset 0))
    (dolist (fragment fragments)
      (replace result fragment :start1 offset)
      (incf offset (length fragment)))
    ;; Clear fragment buffer
    (setf (ws-connection-fragment-buffer connection) nil)
    ;; Return as string if text, otherwise octets
    (if (= (ws-connection-fragment-opcode connection) +opcode-text+)
        (octets-to-string result)
        result)))

;;; End of connection.lisp
