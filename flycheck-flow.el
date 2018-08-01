;;; flycheck-flow.el --- Support Flow in flycheck

;; Copyright (C) 2015 Lorenzo Bolla <lbolla@gmail.com>
;;
;; Author: Lorenzo Bolla <lbolla@gmail.com>
;; Created: 16 Septermber 2015
;; Version: 1.1
;; Package-Requires: ((flycheck "0.18") (json "1.4"))

;;; Commentary:

;; This package adds support for flow to flycheck.  It requires
;; flow>=0.20.0.

;; To use it, add to your init.el:

;; (require 'flycheck-flow)
;; (add-hook 'javascript-mode-hook 'flycheck-mode)

;; You want to use flow in conjunction with other JS checkers.
;; E.g. to use with gjslint, add this to your init.el
;; (flycheck-add-next-checker 'javascript-gjslint 'javascript-flow)

;; For coverage warnings add this to your init.el
;; (flycheck-add-next-checker 'javascript-flow 'javascript-flow-coverage)

;;; License:

;; This file is not part of GNU Emacs.
;; However, it is distributed under the same license.

;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Code:
(require 'flycheck)
(require 'json)

(flycheck-def-args-var flycheck-javascript-flow-args javascript-flow)
(customize-set-variable 'flycheck-javascript-flow-args '())

(defun flycheck-flow--parse-json (output checker buffer)
  "Parse flycheck json OUTPUT generated by CHECKER on BUFFER."
  (let* ((json-object-type 'alist)
         (json-array-type 'list)
         (flow-json-output (json-read-from-string output))
         (flow-errors-list (cdr (assq 'errors flow-json-output)))
         message-kind
         message-level
         message-code-reason
         message-filename
         message-line
         message-column
         message-descr
         errors)
    (dolist (error-message flow-errors-list)
      ;; The structure for each `error-message' in `flow-errors-list' is like this:
      ;; ((kind . `message-kind')
      ;;  (level . `message-level')
      ;;  (message ((descr . `message-code-reason')
      ;;            (loc (source . `message-filename')
      ;;                 (start (line . `message-line') (column . `message-column'))))
      ;;           ((descr . `message-descr'))))
      (let-alist error-message
        (setq message-kind .kind)
        (setq message-level (intern .level))

        (let-alist (car .message)
          (setq message-code-reason .descr
                message-filename .loc.source
                message-line .loc.start.line
                message-descr .descr
                message-column .loc.start.column))

        (let-alist (car (cdr .message))
          (when (string= .type "Comment")
            (setq message-descr .descr))))

      (when (string= message-kind "parse")
        (setq message-descr message-kind))

      (push (flycheck-error-new-at
             message-line
             message-column
             message-level
             message-descr
             :id message-code-reason
             :checker checker
             :buffer buffer
             :filename message-filename)
            errors))
    (nreverse errors)))

(defun read-first-line ()
  "Return first line of current buffer."
  (save-excursion
    (goto-char (point-min))
    (let ((b (point))
          (e (progn (end-of-line) (point))))
      (buffer-substring-no-properties b e))))

(defun flycheck-flow-tag-present-p ()
  "Return true if the '// @flow' or '/* @flow */' tag is present in
   the first line of current buffer."
  (string-match-p "^\\(//+ *@flow\\|/\\* @flow \\*/\\)" (read-first-line)))

(defun flycheck-flow--predicate ()
  "Shall we run the checker?"
  (and
   buffer-file-name
   (file-exists-p buffer-file-name)
   (locate-dominating-file buffer-file-name ".flowconfig")
   (flycheck-flow-tag-present-p)))

(flycheck-define-checker javascript-flow
    "A JavaScript syntax and style checker using Flow.

See URL `http://flowtype.org/'."
    :command (
              "flow"
              "check-contents"
              (eval flycheck-javascript-flow-args)
              "--json"
              "--from" "emacs"
              "--color=never"
              source-original)
    :standard-input t
    :predicate flycheck-flow--predicate
    :error-parser flycheck-flow--parse-json
    ;; js3-mode doesn't support jsx
    :modes (js-mode js-jsx-mode js2-mode js2-jsx-mode js3-mode web-mode rjsx-mode))

(flycheck-define-checker javascript-flow-coverage
  "A coverage checker for Flow.

See URL `http://flowtype.org/'."
  :command (
            "flow"
            "coverage"
            (eval flycheck-javascript-flow-args)
            "--json"
            "--from" "emacs"
            "--path" source-original)
  :standard-input t
  :predicate flycheck-flow--predicate
  :error-parser
  (lambda (output checker buffer)
    (let* ((json-array-type 'list)
           (json-object-type 'alist)
           (locs (condition-case nil
                     (let ((report (json-read-from-string output)))
                       (alist-get 'uncovered_locs (alist-get 'expressions report)))
                   (error nil))))
      (mapcar (lambda (loc)
                (let ((start (alist-get 'start loc))
                      (end (alist-get 'end loc)))
                  (flycheck-error-new
                   :buffer buffer
                   :checker 'javascript-flow-coverage
                   :filename buffer-file-name
                   :line (alist-get 'line start)
                   :column (alist-get 'column start)
                   :message (format "no-coverage-to (%s . %s)"
                                    (alist-get 'line end)
                                    (alist-get 'column end))
                   :level 'warning)))
              locs)))
  ;; js3-mode doesn't support jsx
  :modes (js-mode js-jsx-mode js2-mode js2-jsx-mode js3-mode rjsx-mode))

(add-to-list 'flycheck-checkers 'javascript-flow)
(add-to-list 'flycheck-checkers 'javascript-flow-coverage t)

;; allows eslint checks such as unused variables in addition to javascript-flow checker
(flycheck-add-next-checker 'javascript-flow '(t . javascript-eslint) 'append)

(provide 'flycheck-flow)
;;; flycheck-flow.el ends here
