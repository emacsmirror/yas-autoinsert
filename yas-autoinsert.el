;;; yas-autoinsert.el --- Autoinsert trigger for YASnippet  -*- lexical-binding: t; -*-

;; Copyright (C) 2015, 2016, 2018, 2020  Wieland Hoffmann
;; Copyright (C) 2023 Piknik
;; Copyright (C) 2024-2026 Romain Châtel

;; Author: Wieland Hoffmann <themineo+yatemplate@gmail.com>
;;         Piknik <https://github.com/piknik>
;;         Romain Châtel <rchastel@protonmail.com>
;; Maintainer: Romain Châtel <rchastel@protonmail.com>
;; URL: https://gitlab.com/rchastel1/emacs/yas-autoinsert
;; Version: 1.0.1
;; Package-Requires: ((emacs "25.1") (yasnippet "0.8.1"))
;; Keywords: editing, files, convenience

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package bridges the gap between YASnippet and autoinsert.  By
;; populating `auto-insert-alist' with YASnippet templates and automatically
;; expanding their content after insertion using `auto-insert-mode'.  It's an
;; easy way to create dynamic file templates.  Simply turn on
;; `yas-autoinsert-mode' global minor mode and call
;; `yas-autoinsert-register-all' somewhere in your Emacs initialization file to
;; populate `auto-insert-alist' with templates from YASnippet directories.

;; Of course, you will need to enable `auto-insert-mode' to have the snippet
;; inserted and expanded into new files.

;; Each template with `autoinsert' in its `group' property will be turned into a
;; new element to `push' onto `auto-insert-alist'.  Its `condition' property
;; will become the conditions for insertion and expansion of the template and
;; must conform to the syntax alowed by autoinsert for the `car' of
;; `auto-insert-alist' ie :
;;
;; condition            <- "'" ? (single-conditon / condition-list)
;; condition-list       <- "(" single-conditon * ")"
;; single-condition     <- "'" ? (simple-condition / documented-condition)
;; documented-condition <- "(" simple-condition . description ")"
;; simple-condition     <- string-regexp / major-mode-symbol
;; description          <- string

;; The autoinsert `action' will be a vector of actions that first inserts the
;; content of the template and then expands the content of the buffer
;; with `yas-expand-snippet', so you can use everything YASnippet offers in the
;; template.
;;
;; If a condition list is given, each condition will be inserted in order along
;; with the same action.
;; If you do not specify a condition, it will be determined by the snippet's
;; major mode.

;; To guarantee a particular order, snippets are grouped by mode and then
;; inserted onto `auto-insert-alist' in lexicographic order (according to
;; `string-lessp') taking their `name' property as key for the sort.  The order
;; of insertion for snippets of different modes is random.
;;
;; This means that a snippet directory looking like this:
;;
;; snippets
;; ├── emacs-lisp-mode
;; │   ├── `all' <`name: ALL' and `condition: "*.el"'>
;; │   └── `init' <`name: init' and `condition: "init.el"'>
;; └── python-mode
;;     ├── `all' <`name: ALL' and `condition: "*.py"'>
;;     └── `init' <`name: init' and `condition: "__init__.py"'>
;;
;; will results to situations where init templates will be inserted before ALL
;; ones for example :
;;
;;          (("init.el" . ACTION)
;;           ("*.el" . ACTION)
;;           ("__init__.py" . ACTION)
;;           ("*.py" . ACTION))
;;
;; since upper case names will have higher numerical value than lower case ones.

;; Finally, whenever you save your snippet using the usual YASnippet mechanisms,
;; your `autoinsert' templates will load into `auto-insert-alist'.

;; TL;DR:
;;
;;   Basic steps to setup (assuming yasnippet is enabled):
;;
;;    (require 'yasnippet)
;;    (auto-insert-mode +1)
;;    (require 'yas-autoinsert)
;;    (yas-autoinsert +1)
;;    (yas-autoinsert-register-all)
;;
;;   Snippet examples:
;;
;;     Simple regexp condition
;;
;;       # -*- mode: snippet -*-
;;       # name: README
;;       # key: readme
;;       # group: autoinsert
;;       # condition: "\\`README\\(\\.org\\)?\\'"
;;       # --
;;       #+title:  README
;;       #+date:   ${1:`(format-time-string \"%Y-%m-%d\")`}
;;
;;       * $2
;;       ** Getting started
;;
;;       $0
;;
;;     Major-mode condition:
;;
;;       # -*- mode: snippet -*-
;;       # name: ORG
;;       # key: org
;;       # group: autoinsert
;;       # condition: 'org-mode
;;       # --
;;       #+title:  ${1:Example Org File}
;;       #+date:   ${2:`(format-time-string "%Y-%m-%d")`}
;;
;;       * $0
;;
;;     Documented condition:
;;
;;       # -*- mode: snippet -*-
;;       # name: guix-channel
;;       # key: .gc
;;       # group: autoinsert
;;       # condition: ("\\.guix-channel\\'" ."Guix channel definition template")
;;       # --
;;       ;; -*- mode: scheme; coding: utf-8 -*-
;;       ;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;;       (channel
;;        (version 0)
;;        (keyring-reference "${1:keyring}")
;;        (url "https://gitlab.com/rchastel1/${2:
;;             `(file-name-base
;;                (directory-file-name
;;                  (file-name-directory buffer-file-name)))`}.git")
;;        $0)
;;
;;     Condition list:
;;
;;       # -*- mode: snippet -*-
;;       # name: R6RS
;;       # key: r6
;;       # group: autoinsert
;;       # condition: (("\\.sls\\'" . "R6RS scheme template") scheme-mode)
;;       # --
;;       ;; -*- mode: scheme; coding: utf-8 -*-
;;       ;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;;       #!r6rs
;;
;;       (library ($1)
;;         (export )
;;         (import
;;           (rnrs (6))
;;           $2)
;;
;;         $0
;;         )
;;
;;; Code:

(require 'seq)
(require 'autoinsert)
;; (require 'cl-lib)
(require 'yasnippet)

;;------------------------------------------------------------------------------
;; Compat utilities
(defun yas-autoinsert--always (&rest _)
  "Always return t."
  t)

(defun yas-autoinsert--ignore (&rest _)
  "Always return nil."
  nil)

;;------------------------------------------------------------------------------
;; Public API
;; -- Mode
(defgroup yas-autoinsert
  nil
  "An autoinsert trigger mechanism for YASnippet templates."
  :prefix "yas-autoinsert-"
  :group 'editing
  :group 'files
  :group 'convenience)

;;;###autoload
(define-minor-mode yas-autoinsert-mode
  "Toggle yas-autoinsert mode, a global minor mode.

When yas-autoinsert is enabled, any template defined with YASnippet
and containing `autoinsert' in its `group' property is automatically inserted
into `auto-insert-alist' for automatic insertion and expansion with its
`condition' property value serving as `autoinsert' conditions."
  :lighter " yai"
  :global t
  (cond
   ((and yas-autoinsert-mode (featurep 'yas-autoinsert))
    (yas--message 4 "Enabling yas-autoinsert ...")
    (add-hook 'yas-after-reload-hook #'yas-autoinsert--register-all)
    (add-hook 'after-save-hook #'yas-autoinsert--register-snippet))
   (t
    (yas--message 4 "Disabling yas-autoinsert ...")
    (remove-hook 'yas-after-reload-hook #'yas-autoinsert--register-all)
    (remove-hook 'after-save-hook #'yas-autoinsert--register-snippet))))

;; -- Commands
(defun yas-autoinsert-snippetp (maybe-autoinsert)
  "Tell if a YASnippet template is a `yas-autoinsert' one.

Return t if MAYBE-AUTOINSERT contains `autoinsert' in its `group' property, nil
otherwise."
  (declare (modes yas-minor-mode))
  (interactive
   (list (yas-autoinsert--lookup-snippet nil nil t)))
  (cl-assert (yas--template-p maybe-autoinsert) "not a YASnippet template")
  (let* ((is-autoinsert-template
          (member "autoinsert" (yas--template-group maybe-autoinsert)))
         (is-autoinsert-template
          (and is-autoinsert-template (car is-autoinsert-template))))
    (if (called-interactively-p 'any)
        (message "%s" is-autoinsert-template)
      is-autoinsert-template)))

(defun yas-autoinsert-deregister-all ()
  "Remove all YASnippet auto-inserted templates from `auto-insert-alist'."
  (declare (modes auto-insert-mode))
  (interactive)
  (setq auto-insert-alist
        (seq-filter (lambda (e) (not (yas-autoinsert-alist-entryp e)))
                    auto-insert-alist)))

;;;###autoload
(defun yas-autoinsert-register-all ()
  "Register all YASnippet `autoinsert' templates.

Templates are picked from current YASnippet tables and inserted into
`auto-insert-alist'."
  (declare (modes auto-insert-mode yas-minor-mode))
  (interactive)
  (yas-reload-all t))

(defun yas-autoinsert-register-snippet (&optional name mode)
  "Register a YASnippet snippet into `auto-insert-alist'.

Search for a snippet named NAME for MODE in the YASnippet tables.
When found push it onto `auto-insert-alist' ensuring no other snippets with the
same conditions exists in the list.

If NAME is omitted, prompts the user for suitable NAME and MODE values.
If only MODE is omitted, sets it to the current `major-mode' value.

If the snippet `condition' property is a list, registers the same
snippet template for each condition in the list."
  (declare (modes auto-insert-mode yas-minor-mode))
  (interactive)
  (yas-autoinsert--register-snippet
   (yas-autoinsert--lookup-snippet name mode t) t))

(defun yas-autoinsert-deregister-snippet (&optional name mode)
  "Deregisters a YASnippet snippet from `auto-insert-alist'.

Search for a snippet named NAME for MODE in the YASnippet tables.
When found deletes its entries from `auto-insert-alist'.

If NAME is omitted, prompts the user for suitable NAME and MODE values.
If only MODE is omitted, sets it to the current `major-mode' value.

If the snippet `condition' property is a list, deregisters all of
them."
  (declare (modes auto-insert-mode yas-minor-mode))
  (interactive)
  (yas-autoinsert--deregister-snippet
   (yas-autoinsert--lookup-snippet name mode t)))

(defun yas-autoinsert-alist ()
  "Return all YASnippet auto-inserted entries from `auto-insert-alist'."
  (interactive)
  (seq-filter #'yas-autoinsert-alist-entryp auto-insert-alist))

(defun yas-autoinsert-conditionp (maybe-yas-autoinsert-condition)
  "Tell if MAYBE-YAS-AUTOINSERT-CONDITION is supported.

To be a `yas-autoinsert' condition, it must match the following grammar:

 condition            <- \"'\" ? (single-conditon / condition-list)
 condition-list       <- \"(\" single-conditon * \")\"
 single-condition     <- \"'\" ? (simple-condition / documented-condition)
 documented-condition <- \"(\" simple-condition . description \")\"
 simple-condition     <- string-regexp / major-mode-symbol
 description          <- string

Useful for debugging purpose."
  (yas-autoinsert--parse-condition* maybe-yas-autoinsert-condition
                                    #'yas-autoinsert--always
                                    #'yas-autoinsert--always
                                    #'yas-autoinsert--ignore))

(defun yas-autoinsert-alist-entryp (maybe-yas-autoinsert-alist-entry)
  "Tell if MAYBE-YAS-AUTOINSERT-ALIST-ENTRY was created by `yas-autoinsert'.

Useful for debugging purpose"
  (let* ((is-cons (consp maybe-yas-autoinsert-alist-entry))
         (entry (and is-cons (cdr maybe-yas-autoinsert-alist-entry)))
         (is-array (arrayp entry))
         (action (and is-array (aref entry 1))))
    (and action (eq #'yas-autoinsert--expand-buffer action))))

(defun yas-autoinsert-alist-entry-eqv (lhs rhs)
  "Tell if 2 `auto-insert-alist' entries are equivalent.

Return t if LHS and RHS have the same key ignoring docstrings, nil otherwise.

Useful for debugging purpose."
  (let* ((lhs-key (yas-autoinsert--canonical-entry-key lhs))
         (rhs-key (yas-autoinsert--canonical-entry-key rhs)))
    (equal lhs-key rhs-key)))


;;------------------------------------------------------------------------------
;; Private API
(defun yas-autoinsert--snippet-mode-from-path (snippet-file-path)
  "Gets a YASnippet snippet mode from its SNIPPET-FILE-PATH."
  (intern
   (file-name-nondirectory
    (directory-file-name (file-name-directory snippet-file-path)))))

(defun yas-autoinsert--lookup-snippet (name mode defaults-to-user?)
  "Return a snippet named NAME for MODE from YASnippet tables.

If NAME is nil and DEFAULTS-TO-USER? is not, prompts the user for suitable
NAME and MODE values.
If only MODE is nil, sets it to the current `major-mode' value.

If no snippet can be found returns nil."
  (let ((name+mode
         (if name (list name (or mode major-mode))
           (if (derived-mode-p 'snippet-mode)
               (let ((mode (yas-autoinsert--snippet-mode-from-path
                            (expand-file-name (buffer-file-name))))
                     (pos (point)))
                 (goto-char (point-min))
                 (unwind-protect
                     (when (re-search-forward
                            "^# *name *: *\\(.*?\\)[[:space:]]*$"
                            nil t)
                       (let* ((name (match-string-no-properties 1)))
                         (list name mode)))
                   (goto-char pos)))
             (if defaults-to-user?
                 (list (read-string "snippet name: " nil (buffer-name))
                       (intern (read-string "snippet mode: " nil major-mode)))
               nil)))))
    (when name+mode (apply #'yas-lookup-snippet name+mode))))

(defun yas-autoinsert--canonical-entry-key (entry)
  "Retrives the `canonical' key of an `auto-insert-alist' ENTRY.

Return the key of ENTRY without its optional docstring.
Throws an error if ENTRY is not a valid `auto-insert-alist' one."
  (pcase entry
    (`((,key . ,_docstring) . ,_action) key)
    (`(,key . ,_action) key)
    (_ (error "Not a valid `auto-insert-alist' entry %S" entry))))

(defun yas-autoinsert--single-conditionp (maybe-condition)
  "Check if an object is a suitable single condition.

Return t if MAYBE-CONDITION follows the folowing grammar :

 single-condition     <- \"'\" ? (simple-condition / documented-condition)
 documented-condition <- \"(\" simple-condition . description \")\"
 simple-condition     <- string-regexp / major-mode-symbol
 description          <- string"
  (pcase maybe-condition
    ((or (pred stringp) (pred symbolp)) t)
    (`(quote ,(or (pred stringp) (pred symbolp))) t)
    (`(,(or (pred stringp) (pred symbolp)) . ,(pred stringp)) t)
    (`(quote (,(or (pred stringp) (pred symbolp)) . ,(pred stringp))) t)
    (_ nil)))

(defun yas-autoinsert--parse-condition* (condition ok ok* err)
  "Parse an YASnippet CONDITION into a list of `autoinsert' conditions.

OK, OK* and ERR are continuations called respectively with:
- the sole condition found
- the list of conditions found
- the first object found that is not a valid condition."
  (pcase condition
    ((pred yas-autoinsert--single-conditionp) (funcall ok condition))
    (`(quote ,quoted-condition)
     (yas-autoinsert--parse-condition* quoted-condition ok ok* err))
    ((pred listp)
     (funcall
      ok*
      (mapcar (lambda (maybe-condition)
                (if (yas-autoinsert--single-conditionp maybe-condition)
                    maybe-condition
                  (funcall err maybe-condition)))
              condition)))
    (_ (funcall err condition))))

(defun yas-autoinsert--parse-condition (condition)
  "Parse an YASnippet CONDITION into a list of `autoinsert' conditions.

Throws an error if a non valid condition is found."
  (yas-autoinsert--parse-condition*
   condition
   (lambda (simple-condition)
     (list
      (pcase simple-condition
        (`(quote ,quoted-condition) quoted-condition)
        (_ simple-condition))))
   #'reverse
   (lambda (faulty-condition)
     (error "Not a valid `yas-autoinsert' condition: %S" faulty-condition))))

(defun yas-autoinsert--deregister-condition (condition)
  "Remove an entry from `auto-insert-alist' based on its CONDITION.

Two entries have the same CONDITION if they string or symbol value are equal."
  (let ((fake-entry (cons condition t)))
    (setq auto-insert-alist
          (seq-filter
           (lambda (insert-entry)
             (and (yas-autoinsert-alist-entryp insert-entry)
                  (yas-autoinsert-alist-entry-eqv insert-entry
                                                  fake-entry)))
           auto-insert-alist))))

(defun yas-autoinsert--register-snippet (&optional snippet enforce-unique?)
  "Register a `yas-autoinsert' SNIPPET object into `auto-insert-alist'.

If the SNIPPET condition is a list, it registers the same SNIPPET
template for each condition in the condition list.

If ENFORCE-UNIQUE? is t, ensures that any newly inserted SNIPPET template
replaces any existing one in `auto-insert-alist' with the same condition key."
  (let ((snippet* (or snippet (yas-autoinsert--lookup-snippet nil nil nil)))
        (enforce-unique (if snippet enforce-unique? t)))
    (when (and snippet* (yas-autoinsert-snippetp snippet*))
      (yas--message 4 "found auto-insert snippet %s"
                    (yas--template-name snippet*))
      (let* ((condition (or (yas--template-condition snippet*)
                            (yas-autoinsert--snippet-mode-from-path
                             (yas--template-get-file snippet*))))
             (content (yas--template-content snippet*))
             (conditions (yas-autoinsert--parse-condition condition))
             (insert-template (lambda () (insert content))))
        (dolist (condition conditions)
          (when enforce-unique
            (yas-autoinsert--deregister-condition condition))
          (push (cons condition
                      (vector
                       insert-template
                       #'yas-autoinsert--expand-buffer))
                auto-insert-alist))))))

(defun yas-autoinsert--deregister-snippet (snippet)
  "Deregisters a SNIPPET from `auto-insert-alist'.

If the SNIPPET condition is a list, deregisters all of them."
  (let* ((condition (yas--template-condition snippet))
         (conditions (yas-autoinsert--parse-condition condition)))
    (dolist (condition conditions)
      (yas-autoinsert--deregister-condition condition))))

(defun yas-autoinsert--register-all ()
  "Register autoinserts from current YASnippet tables.

Automatically called by `yas-after-reload-hook'."
  (yas-autoinsert-deregister-all)
  (let ((to-register (list)))
    (maphash
     (lambda (_mode-sym mode)
       (maphash
        (lambda (_key snippets)
          (maphash
           (lambda (_snippet-name snippet)
             (when (yas-autoinsert-snippetp snippet)
               (add-to-list 'to-register snippet)))
           snippets))
        (yas--table-hash mode)))
     yas--tables)
    (setq to-register
          (sort to-register
                (lambda (lhs rhs)
                  (string-lessp (yas--template-name lhs)
                                (yas--template-name rhs)))))
    (dolist (snippet to-register)
      (yas-autoinsert--register-snippet snippet))))

(defun yas-autoinsert--expand-buffer ()
  "Expands the current whole buffer with `yas-expand-snippet'."
  (yas-expand-snippet (buffer-string) (point-min) (point-max)))

(provide 'yas-autoinsert)
;;; yas-autoinsert.el ends here
