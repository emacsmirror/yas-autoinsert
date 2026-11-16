;;; yas-autoinsert.el --- Autoinsert trigger for YASnippet  -*- lexical-binding: t; -*-

;; Copyright (C) 2015, 2016, 2018, 2020  Wieland Hoffmann
;; Copyright (C) 2023 Piknik
;; Copyright (C) 2024-2026 Romain Châtel

;; Authors: Wieland Hoffmann <themineo+yatemplate@gmail.com>
;;          Piknik <https://github.com/piknik>
;;          Romain Châtel <rchastel@protonmail.com>
;; Maintainer: Romain Châtel <rchastel@protonmail.com>
;; URL: https://gitlab.com/rchastel1/yas-autoinsert
;; Version: 0.0.1
;; Package-Requires: ((emacs "24.1") (yasnippet "0.8.1"))
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

;; This package bridges the gap between YASnippet and autoinsert. By
;; populating `auto-insert-alist' with YASnippet templates and automatically
;; expanding their content after insertion using `auto-insert-mode'. It's an
;; easy way to create dynamic file templates. Simply turn on
;; `yas-autoinsert-mode' global minor mode and call
;; `yas-autoinsert-register-all' somewhere in your Emacs initialization file to
;; populate `auto-insert-alist' with templates from YASnippet directories.

;; Of course, you will need to enable `auto-insert-mode' to have the snippet
;; inserted and expanded into new files.

;; Each snippet with `autoinsert' in its `group' directive will be turned into a
;; new element to `push' onto `auto-insert-alist'. Its `condition' directive
;; will become the conditions for insertion and expansion of the template and must
;; conform to the syntax alowed by autoinsert for the `car' of `auto-insert-alist'
;; ie :
;;
;; condition            <- "'" ? (single-conditon / condition-list)
;; condition-list       <- "(" single-conditon * ")"
;; single-condition     <- "'" ? (simple-condition / documented-condition)
;; documented-condition <- "(" simple-condition . description ")"
;; simple-condition     <- string-regexp / major-mode-symbol
;; description          <- string

;; The autoinsert `action' will be a vector of actions that first inserts the
;; content of the snippet template and then expands the content of the buffer
;; with `yas-expand-snippet', so you can use everything YASnippet offers in the
;; template.
;;
;; If a condition list is given, each condition will be inserted in order along
;; with the same action.
;; If you do not specify a condition, it will be determined by the snippet's
;; major mode.

;; To guarantee a particular order, snippets are grouped by mode and then
;; inserted onto `auto-insert-alist' in lexicographic order (according to
;; `string-lessp') taking their `name' directive as key for the sort. The order
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
;;          (("init.el" . ACTION)           (("__init__.py" . ACTION)
;;           ("*.el" . ACTION)         or    ("*.py" . ACTION)
;;           ("__init__.py" . ACTION)        ("init.el" . ACTION)
;;           ("*.py" . ACTION))              ("*.el" . ACTION))
;;
;; since upper case names will have higher numerical value than lower case ones.

;; Finally, whenever you save your snippet using the usual YASnippet mechanisms,
;; your `autoinsert' templates will load into `auto-insert-alist'.

;; TL;DR:
;;
;;   Basic steps to setup:
;;
;;    (require 'yasnippet)
;;    (yas-global-mode +1)
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
;;        (url "https://gitlab.com/rchastel1/${2:`(file-name-base (directory-file-name (file-name-directory buffer-file-name)))`}.git")
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
;;           $2))
;;
;;       $0

;;; Code:

(require 'seq)
(require 'autoinsert)
;; (require 'cl-lib)
(require 'yasnippet)

;;------------------------------------------------------------------------------
;; Public API
;; -- Mode
(defgroup yas-autoinsert
  nil
  "An autoinsert trigger mechanism for YASnippet snippets"
  :prefix "yas-autoinsert-"
  :group 'editing
  :group 'files
  :group 'convenience)

;;;###autoload
(define-minor-mode yas-autoinsert-mode
  "Toggle yas-autoinsert mode, a global minor mode.

When yas-autoinsert is enabled, any snippet template defined with YASnippet
and containing `autoinsert' in its `group' directive is automatically inserted
into `auto-insert-alist' for automatic insertion and expansion with its
`condition' directive value serving as `autoinsert' conditions."
  :lighter "yai"
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
(defun yas-autoinsert-snippetp (maybe-autoinsert-snippet &optional interactive)
  "Tells if a YASnippet object is a `yas-autoinsert' one.

Returns `t' if it contains `autoinsert' in its `group' directive, `nil'
otherwise."
  (declare (modes yas-minor-mode))
  (interactive
   (let ((snippet (yas-autoinsert--lookup-snippet nil nil t)))
     (list snippet t)))
  (let* ((is-autoinsert-snippet
          (member "autoinsert" (yas--template-group maybe-autoinsert-snippet)))
         (is-autoinsert-snippet
          (and is-autoinsert-snippet (car is-autoinsert-snippet))))
    (if interactive (message "%s" is-autoinsert-snippet)
      is-autoinsert-snippet)))

(defun yas-autoinsert-deregister-all ()
  "Removes all YASnippet autoinserts from `auto-insert-alist'."
  (declare (modes auto-insert-mode))
  (interactive)
  (setq auto-insert-alist
        (seq-filter (lambda (e) (not (yas-autoinsert-alist-entryp e)))
                    auto-insert-alist)))

;;;###autoload
(defun yas-autoinsert-register-all ()
  "Registers all `autoinsert' templates from current YASnippet tables into
`auto-insert-alist'."
  (declare (modes auto-insert-mode yas-minor-mode))
  (interactive)
  (yas-reload-all t))

(defun yas-autoinsert-register-snippet (&optional name mode)
  "Registers a YASnippet snippet into `auto-insert-alist'.

Search for a snippet named `name' for mode `mode' in the YASnippet tables.
When found push it onto `auto-insert-alist' ensuring no other snippets with the
same conditions exists in the list.

If `name' is omitted, prompts the user for suitable `name' and `mode' values.
If only `mode' is omitted, sets it to the current `major-mode' value.

If the snippet `condition' directive is a list, registers the same
snippet template for each condition in the list."
  (declare (modes auto-insert-mode yas-minor-mode))
  (interactive)
  (yas-autoinsert--register-snippet
   (yas-autoinsert--lookup-snippet name mode t) t))

(defun yas-autoinsert-deregister-snippet (&optional name mode)
  "Deregisters a YASnippet snippet from `auto-insert-alist'

Search for a snippet named `name' for mode `mode' in the YASnippet tables.
When found deletes its entries from `auto-insert-alist'.

If `name' is omitted, prompts the user for suitable `name' and `mode' values.
If only `mode' is omitted, sets it to the current `major-mode' value.

If the snippet `condition' directive is a list, deregisters all of
them."
  (declare (modes auto-insert-mode yas-minor-mode))
  (interactive)
  (yas-autoinsert--deregister-snippet
   (yas-autoinsert--lookup-snippet name mode t)))

(defun yas-autoinsert-alist ()
  "Returns all yas-autoinsert entries from `auto-insert-alist'"
  (interactive)
  (seq-filter #'yas-autoinsert-alist-entryp auto-insert-alist))

(defun yas-autoinsert-conditionp (maybe-yas-autoinsert-condition)
  "Tells if `maybe-autoinsert-condition' is a valid condition value for a
`yas-autoinsert' snippet

A condition directive must match the following grammar:

 condition            <- \"'\" ? (single-conditon / condition-list)
 condition-list       <- \"(\" single-conditon * \")\"
 single-condition     <- \"'\" ? (simple-condition / documented-condition)
 documented-condition <- \"(\" simple-condition . description \")\"
 simple-condition     <- string-regexp / major-mode-symbol
 description          <- string

Useful for debugging purpose"
  (yas-autoinsert--parse-condition*
   maybe-yas-autoinsert-condition #'always #'always #'ignore))

(defun yas-autoinsert-alist-entryp (maybe-yas-autoinsert-alist-entry)
  "Tells if an object is an `auto-insert-alist' entry created by
`yas-autoinsert'.

Useful for debugging purpose"
  (ignore-errors (eq #'yas-autoinsert--expand-buffer
                     (aref (cdr maybe-yas-autoinsert-alist-entry) 1))))

(defun yas-autoinsert-alist-entry-eqv (lhs rhs)
  "Tells if 2 `auto-insert-alist' entries are equivalent.

Returns `t' if both have the same key ignoring docstrings, `nil' otherwise.

Useful for debugging purpose"
  (let* ((lhs-key (yas-autoinsert--canonical-entry-key lhs))
         (rhs-key (yas-autoinsert--canonical-entry-key rhs)))
    (equal lhs-key rhs-key)))


;;------------------------------------------------------------------------------
;; Private API
(defun always (&rest _) t)
(defun ignore (&rest _) nil)
(defun yas-autoinsert--snippet-mode-from-path (snippet-file-path)
  "Gets a YASnippet snippet mode from its file path"
  (intern
   (file-name-nondirectory
    (directory-file-name (file-name-directory snippet-file-path)))))

(defun yas-autoinsert--lookup-snippet (name mode defaults-to-user?)
  "Returns a snippet named `name' for mode `mode' from YASnippet tables.

If `name' is nil and `defaults-to-user?' is not, prompts the user for suitable
`name' and `mode' values.
If only `mode' is nil, sets it to the current `major-mode' value.

If no snippet can be found returns nil. "
  (let ((name+mode
         (if name (list name (or mode major-mode))
           (if (eq major-mode 'snippet-mode)
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
  "Retrives the `canonical' key of an `auto-insert-alist' entry.

Returns the key of `entry' without its optional docstring.
Throws an error if `entry' is not a valid `auto-insert-alist' one."
  (pcase entry
    (`((,key . ,_docstring) . ,_action) key)
    (`(,key . ,_action) key)
    (_ (error "not a valid `auto-insert-alist' entry %S" entry))))

(defun yas-autoinsert--single-conditionp (maybe-condition)
  "Checks if an object is a suitable single condition

Condition must follow the folowing grammar:

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
  "Parses an YASnippet condition into a list of conditions suitable for
`auto-insert-alist', cps version.

`ok', `ok*' and `err' are continuations called respectively with:
- the sole condition found
- the list of conditions found
- the first object found that is not a valid condition."
  ;; (message "%S" condition)
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
  "Parses an YASnippet condition into a list of conditions suitable for
`auto-insert-alist'.

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
     (error "not a valid `yas-autoinsert' condition: %S" faulty-condition))))

(defun yas-autoinsert--deregister-condition (condition)
  "Removes an entry from `auto-insert-alist' based on its `condition'.

Two entries have the same `condition' if they string or symbol value are equal."
  (let ((fake-entry (cons condition t)))
    (setq auto-insert-alist
          (seq-filter
           (lambda (insert-entry)
             (and (yas-autoinsert-alist-entryp insert-entry)
                  (yas-autoinsert-alist-entry-eqv insert-entry
                                                  fake-entry)))
           auto-insert-alist))))

(defun yas-autoinsert--register-snippet (&optional snippet? enforce-unique?)
  "Registers a `yas-autoinsert' `snippet' object into `auto-insert-alist'.

If the `snippet' condition is a list, it registers the same `snippet'
template for each condition in the condition list.

If `enforce-unique?' is `t', ensures that any newly inserted `snippet' template
replaces any existing one in `auto-insert-alist' with the same condition key."
  (let ((snippet (or snippet? (yas-autoinsert--lookup-snippet nil nil nil)))
        (enforce-unique (if snippet? enforce-unique? t)))
    (when (and snippet (yas-autoinsert-snippetp snippet))
      (yas--message 4 "found auto-insert snippet %s"
                    (yas--template-name snippet))
      (let* ((condition (or (yas--template-condition snippet)
                            (yas-autoinsert--snippet-mode-from-path
                             (yas--template-get-file snippet))))
             (content (yas--template-content snippet))
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
  "Deregisters a `snippet' from `auto-insert-alist'

If the `snippet' condition is a list, deregisters all of them."
  (let* ((condition (yas--template-condition snippet))
         (conditions (yas-autoinsert--parse-condition condition)))
    (dolist (condition conditions)
      (yas-autoinsert--deregister-condition condition))))

(defun yas-autoinsert--register-all ()
  "Registers autoinserts from current YASnippet tables.

Automatically called by `yas-after-reload-hook'."
  (yas-autoinsert-deregister-all)
  (let ((to-register (list)))
    (maphash
     (lambda (_mode-sym mode)
       ;; (let ((mode-snippets (list)))
       (maphash
        (lambda (_key snippets)
          (maphash
           (lambda (_snippet-name snippet)
             (when (yas-autoinsert-snippetp snippet)
               (add-to-list 'to-register snippet)
               ;; (setq mode-snippets
               ;;       (cl-merge
               ;;        'list
               ;;        mode-snippets
               ;;        (list snippet)
               ;;        (lambda (lhs rhs)
               ;;          (string-lessp (yas--template-name lhs)
               ;;                        (yas--template-name rhs)))))
               ))
           snippets))
        (yas--table-hash mode))
       ;; (setq to-register (nconc mode-snippets to-register))
       ;; )
       )
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
