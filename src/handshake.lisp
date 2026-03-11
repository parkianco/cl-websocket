;;;; handshake.lisp - WebSocket handshake protocol
;;;;
;;;; Implements the WebSocket opening handshake per RFC 6455 Section 4.
;;;; Includes HTTP upgrade request generation and response validation.
;;;;
;;;; Standards: RFC 6455 Section 4 (Opening Handshake)
;;;; Thread Safety: Yes (pure functions)
;;;; Performance: O(n) for header parsing where n is header size

(in-package #:cl-websocket)

;;; ============================================================================
;;; Conditions
;;; ============================================================================

(define-condition websocket-error (error)
  ((message :initarg :message :reader websocket-error-message))
  (:report (lambda (c s)
             (format s "WebSocket error: ~A" (websocket-error-message c)))))

(define-condition websocket-connection-error (websocket-error) ())
(define-condition websocket-protocol-error (websocket-error) ())
(define-condition websocket-handshake-error (websocket-error) ())

;;; ============================================================================
;;; Key Generation
;;; ============================================================================

(defun generate-client-key ()
  "Generate a random Sec-WebSocket-Key for client handshake.

   Per RFC 6455, this is a base64-encoded 16-byte random value.

   Returns: Base64-encoded key string (24 characters)"
  (base64-encode (random-bytes 16)))

(defun compute-accept-key (client-key)
  "Compute Sec-WebSocket-Accept value from client key.

   Per RFC 6455 Section 4.2.2:
   1. Concatenate client key with GUID
   2. Compute SHA-1 hash
   3. Base64 encode the result

   Parameters:
     CLIENT-KEY - Value of Sec-WebSocket-Key header

   Returns: Accept key string"
  (let* ((combined (concatenate 'string
                                (string-trim '(#\Space #\Tab) client-key)
                                +ws-guid+))
         (hash (sha1 combined)))
    (base64-encode hash)))

;;; ============================================================================
;;; Client Handshake Request
;;; ============================================================================

(defun make-handshake-request (host port path &key protocols extensions origin)
  "Generate HTTP upgrade request for WebSocket handshake.

   Parameters:
     HOST - Server hostname
     PORT - Server port
     PATH - Request path (e.g., \"/ws\" or \"/\")
     PROTOCOLS - Optional list of subprotocol names
     EXTENSIONS - Optional list of extension names
     ORIGIN - Optional origin header value

   Returns: (values request-string client-key)"
  (let ((key (generate-client-key)))
    (values
     (with-output-to-string (s)
       (format s "GET ~A HTTP/1.1~C~C" path #\Return #\Linefeed)
       (format s "Host: ~A~@[:~D~]~C~C" host (unless (= port 80) port) #\Return #\Linefeed)
       (format s "Upgrade: websocket~C~C" #\Return #\Linefeed)
       (format s "Connection: Upgrade~C~C" #\Return #\Linefeed)
       (format s "Sec-WebSocket-Key: ~A~C~C" key #\Return #\Linefeed)
       (format s "Sec-WebSocket-Version: 13~C~C" #\Return #\Linefeed)
       (when origin
         (format s "Origin: ~A~C~C" origin #\Return #\Linefeed))
       (when protocols
         (format s "Sec-WebSocket-Protocol: ~{~A~^, ~}~C~C"
                 protocols #\Return #\Linefeed))
       (when extensions
         (format s "Sec-WebSocket-Extensions: ~{~A~^, ~}~C~C"
                 extensions #\Return #\Linefeed))
       (format s "~C~C" #\Return #\Linefeed))
     key)))

;;; ============================================================================
;;; Client Handshake Response Parsing
;;; ============================================================================

(defun parse-handshake-response (response)
  "Parse HTTP response from WebSocket handshake.

   Parameters:
     RESPONSE - HTTP response string

   Returns: Plist with :status-code, :headers, :protocol, :extensions"
  (let* ((lines (split-lines response))
         (status-line (first lines))
         (headers (make-hash-table :test 'equalp)))

    ;; Parse status line
    (unless (and status-line
                 (>= (length status-line) 12)
                 (string= (subseq status-line 0 5) "HTTP/"))
      (error 'websocket-handshake-error
             :message "Invalid HTTP response"))

    (let ((status-code (parse-integer (subseq status-line 9 12) :junk-allowed t)))

      ;; Parse headers
      (loop for line in (rest lines)
            while (and line (> (length line) 0))
            do (let ((colon (position #\: line)))
                 (when colon
                   (let ((name (string-trim '(#\Space #\Tab)
                                            (subseq line 0 colon)))
                         (value (string-trim '(#\Space #\Tab)
                                             (subseq line (1+ colon)))))
                     (setf (gethash name headers) value)))))

      (list :status-code status-code
            :headers headers
            :protocol (gethash "Sec-WebSocket-Protocol" headers)
            :extensions (gethash "Sec-WebSocket-Extensions" headers)))))

(defun validate-handshake-response (response client-key)
  "Validate server's handshake response.

   Parameters:
     RESPONSE - Parsed response plist from parse-handshake-response
     CLIENT-KEY - The Sec-WebSocket-Key that was sent

   Returns: T if valid, signals error otherwise"
  (let ((status (getf response :status-code))
        (headers (getf response :headers)))

    ;; Check status code
    (unless (= status 101)
      (error 'websocket-handshake-error
             :message (format nil "Expected 101 Switching Protocols, got ~D" status)))

    ;; Check Upgrade header
    (let ((upgrade (gethash "Upgrade" headers)))
      (unless (and upgrade (string-equal upgrade "websocket"))
        (error 'websocket-handshake-error
               :message "Missing or invalid Upgrade header")))

    ;; Check Connection header
    (let ((connection (gethash "Connection" headers)))
      (unless (and connection (search "upgrade" (string-downcase connection)))
        (error 'websocket-handshake-error
               :message "Missing or invalid Connection header")))

    ;; Verify accept key
    (let ((accept (gethash "Sec-WebSocket-Accept" headers))
          (expected (compute-accept-key client-key)))
      (unless (and accept (string= accept expected))
        (error 'websocket-handshake-error
               :message (format nil "Invalid Sec-WebSocket-Accept (expected ~A, got ~A)"
                                expected accept))))

    t))

;;; ============================================================================
;;; Utilities
;;; ============================================================================

(defun split-lines (string)
  "Split STRING into lines (handling CRLF and LF)."
  (let ((lines nil)
        (current (make-array 0 :element-type 'character
                               :adjustable t :fill-pointer t)))
    (loop for char across string
          do (cond
               ((char= char #\Return)
                nil) ; Skip CR
               ((char= char #\Linefeed)
                (push (copy-seq current) lines)
                (setf (fill-pointer current) 0))
               (t
                (vector-push-extend char current))))
    (when (> (length current) 0)
      (push (copy-seq current) lines))
    (nreverse lines)))

(defun read-http-response (stream)
  "Read a complete HTTP response from STREAM.

   Reads until double CRLF (end of headers).

   Returns: Response string"
  (let ((result (make-array 0 :element-type 'character
                              :adjustable t :fill-pointer t))
        (crlf-count 0))
    (loop for byte = (read-byte stream nil nil)
          while byte
          do (let ((char (code-char byte)))
               (vector-push-extend char result)
               (cond
                 ((char= char #\Return)
                  nil)
                 ((char= char #\Linefeed)
                  (incf crlf-count)
                  (when (>= crlf-count 2)
                    (return)))
                 (t
                  (setf crlf-count 0)))))
    (coerce result 'string)))

;;; End of handshake.lisp
