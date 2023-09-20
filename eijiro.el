;;; eijiro.el --- Look up a word in the eijiro dictionary. -*- lexical-binding:t -*-

;; Copyright (C) 2019 Tomotaka SUWA <tomotaka.suwa@gmail.com>
;;
;; Author: Tomotaka SUWA <tomotaka.suwa@gmail.com>
;; Version: 0.1.0
;; Package-Version: 20190620.000
;; Package-Requires: ((emacs "25"))
;; Keywords : convenience matching processes
;; URL: https://github.com/t-suwa/eijiro/

;;; Commentary:

;; A simple searching frontend dedicated to the eijiro plain text
;; dictionary and ripgrep.

;;; Installation:

;; 1) Install ripgrep
;;
;;    https://github.com/BurntSushi/ripgrep/releases
;;
;; 2) Acquire eijiro plain text dictionary
;;
;;    https://www.eijiro.jp/get-144.htm
;;
;; 3) Convert character encodings of the dictionary to utf-8
;;
;;    % nkf -w8 -Lu EIJIRO-144x.TXT > ~/etc/eijiro-144x.utf-8
;;
;; 4) Install eijiro.el
;;
;;    M-: (package-install-from-archive "https://github.com/t-suwa/eijiro/")
;;
;; 5) Minimum configuration
;;
;;    - Variable: `eijiro-dictionary'
;;      Bind a valid path of the dictionary.

;;; Usage:

;; 1) Invocation
;;
;; M-x eijiro-lookup
;;
;; You would also like to assign a key binding to it in your
;; ~/.emacs.d/init.el, for example:
;;
;; (global-set-key (kbd "C-c e") 'eijiro-lookup)
;;
;; 2) Choosing search behavior by prefix argument
;;
;; To provide different search behaviors some prefix arguments are
;; being employed:
;;
;; prefix argument	behavior
;; ---------------	-----------------------------------
;; None			match any words contain "WORD"
;; C-u			match any entries begin with "WORD"
;; C-u C-u		match any words "WORD"
;; M-1			match any words begin with "WORD"
;; M-2			match any words contain "WORD"
;; M-3			match any words end with "WORD"

;;; License:

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 2
;; of the License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
;; 02110-1301, USA.

;;; Code:

;; Customization

(defgroup eijiro nil
  "Eijiro"
  :group 'tools
  :group 'matching)

(defcustom eijiro-rg-command
  "rg"
  "Ripgrep executable command name."
  :type 'string
  :group 'eijiro)

(defcustom eijiro-rg-arguments
  (list "--no-line-number"
        "--ignore-case"
        "--color=ansi"
        "--colors=match:bg:red")
  "Default arguments passed to eijiro-rg-command."
  :type '(repeat (string))
  :group 'eijiro)

(defcustom eijiro-rg-max-count
  500
  "Max count of search result."
  :type 'int
  :group 'eijiro)

(defcustom eijiro-dictionary
  "~/etc/eijiro-1446.utf-8"
  "Eijiro plain text dictionary."
  :type 'file
  :group 'eijiro)

(defcustom eijiro-window-height
  20
  "Window height for search result buffer."
  :type 'int
  :group 'eijiro)

(defcustom eijiro-block-label
  "┃"
  "Label string for block."
  :type 'string
  :group 'eijiro)

(defcustom eijiro-annotation-label
  "注) "
  "Label string for annotations."
  :type 'string
  :group 'eijiro)

(defcustom eijiro-example-label
  "ex."
  "Label string for examples."
  :type 'string
  :group 'eijiro)

(defcustom eijiro-indent-width
  6
  "Indent width for example sentences."
  :type 'int
  :group 'eijiro)

(defcustom eijiro-beautify-functions
  '(eijiro-beautify-remove-heading
    eijiro-beautify-examples
    eijiro-beautify-annotations
    eijiro-beautify-matches)
  "A list of beautify functions for search result."
  :type '(repeat function)
  :group 'eijiro)

;; Constants

(defconst eijiro-example-start-indicator
  "■"
  "Start indicator for example sentences.")

(defconst eijiro-annotation-start-indicator
  "◆"
  "Start indicator for annotations.")

(defconst eijiro-regexp-highlight
  (let ((escape-sequence "[[:cntrl:]]\\{1\\}[^m[:cntrl:]]+m")
        (word "\\([^[:cntrl:]]+\\)"))
    (format "\\(\\(?:%s\\)\\{4\\}\\)%s\\(%s\\)"
            escape-sequence word escape-sequence))
  "Regexp for highlight.")

;; Buffer local variables

(defvar-local eijiro-current-action ""
  "Current searching action.")

;; Faces

(defface eijiro-entry-face '((t :inherit font-lock-keyword-face))
  "Face for entries."
  :group 'eijiro)

(defface eijiro-block-face '((t :inherit font-lock-function-name-face))
  "Face for blocks."
  :group 'eijiro)

(defface eijiro-match-face '((t :inherit match))
  "Face for matches."
  :group 'eijiro)

(defvar eijiro-font-lock-keywords
  `(("^\\(.+\\) : " 1 'eijiro-entry-face)
    (,(concat "^" eijiro-block-label ".*$") 0 'eijiro-block-face)))

;; Mode

(defvar eijiro-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "n") 'forward-line)
    (define-key map (kbd "j") 'forward-line)
    (define-key map (kbd "p") 'previous-line)
    (define-key map (kbd "k") 'previous-line)
    (define-key map (kbd "h") 'backward-char)
    (define-key map (kbd "l") 'forward-char)
    (define-key map (kbd "q") 'quit-window)
    map))

;;;###autoload
(define-derived-mode eijiro-mode special-mode "Eijiro"
  (buffer-disable-undo)
  (setq tab-width eijiro-indent-width)
  (setq truncate-lines nil)
  (setq font-lock-defaults '(eijiro-font-lock-keywords
                             keywords-only
                             ignore-case)))

;; Beautify functions

(defun eijiro-beautify-remove-heading ()
  "Remove a first character on each line."
  (while (not (eobp))
    (delete-char 1)
    (forward-line)))

(defun eijiro-beautify-annotations ()
  "Place annotations to new line."
  (let ((regexp (format "\\(%s\\)"
                        eijiro-annotation-start-indicator)))
    (while (re-search-forward regexp nil t)
      (replace-match (concat "\n" eijiro-block-label eijiro-annotation-label)))))

(defun eijiro-beautify-examples ()
  "Place example sentences to new line."
  (let ((regexp (format "%s.\\([^[:multibyte:]]+\\)\\([^%s]+\\)"
                        eijiro-example-start-indicator
                        eijiro-example-start-indicator))
        (replace (format "\n%s%s\t\\1\n%s\t\\2"
                         eijiro-block-label
                         eijiro-example-label
                         eijiro-block-label)))
    (while (re-search-forward regexp nil t)
      (replace-match replace))))

(defun eijiro-beautify-matches ()
  "Highlight matched words."
  (let ((regexp eijiro-regexp-highlight)
        word-list)
    (while (re-search-forward regexp nil t nil)
      (let ((word (match-string-no-properties 2)))
        (unless (member-ignore-case word word-list)
          (highlight-regexp word 'eijiro-match-face)
          (push word word-list))
        (replace-match "\\2")))))

;; Internal functions

(defun eijiro--buffer ()
  "Return buffer for eijiro-lookup."
  (get-buffer-create "*eijiro-lookup*"))

(defun eijiro--error (format &rest args)
  "Display user error with FORMAT and ARGS."
  (apply 'user-error (concat format " (ERROR:eijiro)") args))

(defun eijiro--check-configuration ()
  "Check eijiro configuration."
  (or (executable-find eijiro-rg-command)
      (eijiro--error "Command `%s' does not exist" eijiro-rg-command))
  (or (file-exists-p (file-truename eijiro-dictionary))
      (eijiro--error "Dictionary `%s' does not exist" eijiro-dictionary)))

(defun eijiro--kill-old-process ()
  "Ensure old process is not alive."
  (let ((process (get-buffer-process (eijiro--buffer))))
    (when process
      (if (or (not (eq (process-status process) 'run))
              (eq (process-query-on-exit-flag process) nil)
              (y-or-n-p "[eijiro] Kill old process? "))
          (condition-case ()
              (progn
                (interrupt-process process)
                (sit-for 1)
                (delete-process process))
            (error nil))
        (eijiro--error "Cannot have two processes at once")))))

(defun eijiro--kill-old-window ()
  "Ensure old window is not live."
  (with-current-buffer (eijiro--buffer)
    (let ((window (get-buffer-window)))
      (if (window-live-p window)
          (condition-case ()
              (kill-buffer-and-window)
            (error nil))))))

(defun eijiro--display-result ()
  "Display search result."
  (with-current-buffer (eijiro--buffer)
    (let ((inhibit-read-only t))
      (eijiro-mode)
      (goto-char (point-min))
      (dolist (func eijiro-beautify-functions)
        (save-excursion (funcall func)))
      (force-mode-line-update)
      (set-window-point
       (select-window
        (display-buffer-at-bottom
         (current-buffer)
         `((window-height . ,eijiro-window-height)))
        'no-record)
       (point-min)))))

(defun eijiro--build-command (word)
  "Build shell command line string for searching WORD."
  (let ((args (append (list eijiro-rg-command)
                      eijiro-rg-arguments
                      (list
                       (format "--max-count=%d" eijiro-rg-max-count)
                       "--"
                       (replace-regexp-in-string
                        "\\^"
                        "^."
                        (shell-quote-argument word))
                       (file-truename eijiro-dictionary)))))
    (list shell-file-name
          shell-command-switch
          (mapconcat 'identity args " "))))

(defun eijiro--search-sentinel (process event)
  "Handle EVENT for PROCESS."
  (with-current-buffer (process-buffer process)
    (let ((action eijiro-current-action))
      (pcase (process-status process)
        ('exit
         (if (zerop (buffer-size))
             (message (concat action " got no results."))
           (eijiro--display-result)
           (message (concat action " done."))))
        ('signal
         (eijiro--error (concat action ": " event)))))))

(defun eijiro--search-word (word)
  "Search WORD with ripgrep."
  (with-current-buffer (eijiro--buffer)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (setq eijiro-current-action (format "Searching \"%s\"" word))
      (message (concat eijiro-current-action " ..."))
      (make-process :name "eijiro"
                    :buffer (current-buffer)
                    :command (eijiro--build-command word)
                    :coding (cons 'utf-8 locale-coding-system)
                    :sentinel 'eijiro--search-sentinel))))

;; Command

;;;###autoload
(defun eijiro-lookup (word)
  "Look up the WORD in eijiro dictionary."
  (interactive
   (let* ((transformer
           (pcase current-prefix-arg
             (`(4) (lambda (word) ":entry" (concat "^" word)))
             (`(16) (lambda (word) ":just" (concat "\\b" word "\\b")))
             (1 (lambda (word) ":prefix" (concat "\\b" word "\\B")))
             (2 (lambda (word) ":contain" (concat "\\B" word "\\B")))
             (3 (lambda (word) ":suffix" (concat "\\B" word "\\b")))
             (_ (lambda (word) "" word))))
          (thing (or (and (use-region-p)
                          (buffer-substring-no-properties (region-beginning)
                                                          (region-end)))
                     (thing-at-point 'word 'no-properties)))
          (prompt (format "[eijiro%s] " (documentation transformer t)))
          (word (or thing (read-from-minibuffer prompt))))
     (list (funcall transformer word))))
  (eijiro--check-configuration)
  (eijiro--kill-old-window)
  (eijiro--search-word word))

(provide 'eijiro)
;;; eijiro.el ends here
