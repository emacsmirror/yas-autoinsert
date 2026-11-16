;;; yas-autoinsert-tests.el --- yas-autoinsert tests  -*- lexical-binding: t; -*-

;; Copyright (C) 2024-2026  Romain Châtel

;; Author: Châtel Romain <rchastel@protonmail.com>
;; Keywords:

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

;;

;;; Code:

(require 'buttercup)
(require 'shut-up)
(require 'yas-autoinsert)

(defun nth-elt (element xs)
  "Return zero-indexed position of ELEMENT in list XS, or nil if absent."
  (let ((idx  0))
    (catch 'nth-elt
      (dolist (x  xs)
        (when (equal element x) (throw 'nth-elt idx))
        (setq idx  (1+ idx)))
      nil)))

(defun build-example-snippets (org-snippets-dir scheme-snippets-dir)
  (with-temp-file (concat org-snippets-dir "readme")
    (insert "# -*- mode: snippet -*-
# name: README
# key: readme
# group: autoinsert
# condition: \"\\\\`README\\\\(\\\\.org\\\\)?\\\\'\"
# --
#+title:  README
#+date:   ${1:`(format-time-string \"%Y-%m-%d\")`}

* $2
** Getting started

$0"))

  (with-temp-file (concat org-snippets-dir "org")
    (insert "# -*- mode: snippet -*-
# name: ORG
# key: org
# group: autoinsert
# condition: org-mode
# --
#+title:  ${1:Example Org File}
#+date:   ${2:`(format-time-string \"%Y-%m-%d\")`}"))

  (with-temp-file (concat scheme-snippets-dir "guix-channel")
    (insert "# -*- mode: snippet -*-
# name: guix-channel
# key: .gc
# group: autoinsert
# condition: '(\"\\\\.guix-channel\\\\'\" . \"Guix channel definition template\")
# --
;; -*- mode: scheme; coding: utf-8 -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

(channel
 (version 0)
 (keyring-reference \"${1:keyring}\")
 (url \"https://gitlab.com/rchastel1/${2:`(file-name-base (directory-file-name (file-name-directory buffer-file-name)))`}.git\")
 $0)"))

  (with-temp-file (concat scheme-snippets-dir "default")
    (insert "# -*- mode: snippet -*-
# name: R6RS
# key: r6
# group: autoinsert
# condition: '((\"\\\\.sls\\\\'\" . \"R6RS scheme template\") scheme-mode)
# --
;; -*- mode: scheme; coding: utf-8 -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

#!r6rs

(library ($1)
  (export )
  (import
    (rnrs (6))
    $2))

$0")))

(defvar yas-autoinsert-test-dir)
(defvar yas-autoinsert-test-dir)
(defvar yas-autoinsert-snippets-dir)
(defvar yas-autoinsert-org-snippets-dir)
(defvar yas-autoinsert-scheme-snippets-dir)
(defvar yas-autoinsert-elisp-snippets-dir)

(describe
 "yas-autoinsert"
 (before-all
  (setq
   yas-autoinsert-test-dir
   (file-name-as-directory
    (concat temporary-file-directory "yas-autoinsert-test"))
   yas-autoinsert-snippets-dir
   (file-name-as-directory
    (concat yas-autoinsert-test-dir "snippets"))
   yas-autoinsert-org-snippets-dir
   (file-name-as-directory
    (concat yas-autoinsert-snippets-dir "org-mode"))
   yas-autoinsert-scheme-snippets-dir
   (file-name-as-directory
    (concat yas-autoinsert-snippets-dir "scheme-mode"))
   yas-autoinsert-elisp-snippets-dir
   (file-name-as-directory
    (concat yas-autoinsert-snippets-dir "emacs-lisp-mode"))))
 (before-each
  (mkdir yas-autoinsert-snippets-dir t)
  (mkdir yas-autoinsert-org-snippets-dir t)
  (mkdir yas-autoinsert-scheme-snippets-dir t)
  (mkdir yas-autoinsert-elisp-snippets-dir t)
  (add-to-list 'yas-snippet-dirs yas-autoinsert-snippets-dir)
  (setq default-directory yas-autoinsert-test-dir)

  (with-temp-file (concat yas-autoinsert-elisp-snippets-dir "and")
    (insert "# -*- mode: snippet -*-
# contributor: Xah Lee (XahLee.org)
# name: and
# key: and
# key: a
# --
(and $0)"))

  (with-temp-file (concat yas-autoinsert-scheme-snippets-dir "mode-line")
    (insert "# -*- mode: snippet -*-
# name: Scheme Mode line
# group: scheme
# condition: t
# key: -*-
# --
;; -*- mode:scheme; coding: utf-8 -*-
;; SPDX-License-Identifier: ${1:GPL-3.0-or-later}

$0"))

  (shut-up
    (yas-autoinsert-mode 1)
    (yas-autoinsert-register-all))
  )

 (it "connects to yas-after-reload-hook and after-save-hook on activation"
     (expect yas-after-reload-hook :to-contain #'yas-autoinsert--register-all)
     (expect after-save-hook :to-contain #'yas-autoinsert--register-snippet))


 (it "deconnects from yas-after-reload-hook and after-save-hook on desactivation"
     (yas-autoinsert-mode -1)
     (expect yas-after-reload-hook
             :not :to-contain #'yas-autoinsert--register-all)
     (expect after-save-hook
             :not :to-contain #'yas-autoinsert--register-snippet))

 (it "must not register non autoinsert snippets"
     (expect (yas-autoinsert-alist) :not :to-be-truthy))

 (it "must register autoinsert snippets"
     (build-example-snippets yas-autoinsert-org-snippets-dir
                             yas-autoinsert-scheme-snippets-dir)
     (shut-up (yas-autoinsert-register-all))
     (let* ((entries (yas-autoinsert-alist))
            (keys (mapcar #'car entries)))

       (expect (length entries) :to-equal 5)

       (expect keys :to-contain "\\`README\\(\\.org\\)?\\'")
       (expect keys :to-contain 'org-mode)
       (expect keys :to-contain
               '("\\.guix-channel\\'" . "Guix channel definition template"))
       (expect keys :to-contain '("\\.sls\\'" . "R6RS scheme template"))
       (expect keys :to-contain 'scheme-mode)

       (expect (nth-elt "\\`README\\(\\.org\\)?\\'" keys)
               :to-be-less-than
               (nth-elt 'org-mode keys))
       (expect (nth-elt '("\\.guix-channel\\'" .
                          "Guix channel definition template")
                        keys)
               :to-be-less-than
               (nth-elt '("\\.sls\\'" . "R6RS scheme template") keys))
       (expect (nth-elt '("\\.guix-channel\\'" .
                          "Guix channel definition template")
                        keys)
               :to-be-less-than
               (nth-elt 'scheme-mode keys))
       (expect (nth-elt '("\\.sls\\'" . "R6RS scheme template") keys)
               :to-be-less-than
               (nth-elt 'scheme-mode keys))
       ))


 (it "must not register snippets with same conditions twice"
     (build-example-snippets yas-autoinsert-org-snippets-dir
                             yas-autoinsert-scheme-snippets-dir)
     (shut-up (yas-autoinsert-register-all))
     (let ((entries-first (yas-autoinsert-alist))
           (_ (shut-up (yas-autoinsert-register-all)))
           (entries-second (yas-autoinsert-alist))
           (_ (with-temp-buffer
                (find-file (concat yas-autoinsert-elisp-snippets-dir "and"))
                (insert " ")
                (write-file (concat yas-autoinsert-elisp-snippets-dir "and"))))
           (_ (shut-up (yas-autoinsert-register-all)))
           (entries-third (yas-autoinsert-alist)))
       (expect (length entries-first) :to-equal (length entries-second))
       (expect (length entries-first) :to-equal (length entries-third))))

 (it "must register newly saved autoinsert snippets"
     (shut-up
       (with-temp-buffer
         (org-mode)
         (yas-new-snippet t)
         (insert "org") (newline)
         (insert "# -*- mode: snippet -*-
# name: ORG
# key: org
# group: autoinsert
# condition: 'org-mode
# --
#+title:  ${1:Example Org File}
#+date:   ${2:`(format-time-string \"%Y-%m-%d\")`}")
         (write-file (concat yas-autoinsert-org-snippets-dir "org")))
       )
     (let* ((entries (yas-autoinsert-alist))
            (keys (mapcar #'car entries)))
       (expect (length entries) :to-equal 1)
       (expect keys :to-contain 'org-mode)))

 (it "must deregister deleted autoinsert snippets on next register-all"
     (build-example-snippets yas-autoinsert-org-snippets-dir
                             yas-autoinsert-scheme-snippets-dir)
     (shut-up (yas-autoinsert-register-all))
     (let* ((keys (mapcar #'car (yas-autoinsert-alist)))
            (_ (expect keys :to-contain 'org-mode))
            (_ (delete-file (concat yas-autoinsert-org-snippets-dir "org")))
            (_ (shut-up (yas-autoinsert-register-all)))
            (keys (mapcar #'car (yas-autoinsert-alist))))
       (expect keys :not :to-contain 'org-mode)))

 (after-each
  (yas-autoinsert-mode -1)
  (delete-directory default-directory t))

 )

(provide 'yas-autoinsert-tests)
;;; yas-autoinsert-tests.el ends here
