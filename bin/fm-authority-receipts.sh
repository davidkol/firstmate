#!/usr/bin/env bash
# fm-authority-receipts.sh - find claims made under the captain's authority that
# carry no receipt.
# Usage: fm-authority-receipts.sh <path>...
#   Each path is a Markdown file, or a directory scanned for *.md.
#   Prints one line per unreceipted claim and exits 1; exits 0 when clean.
#
# Why this exists. On 2026-08-03 the captain traced a mechanism he had never
# approved back into a shipped game. Firstmate concluded a ruling of his could
# not be built as stated, substituted its own mechanism, and wrote the
# substitution into the work order under a heading that claimed his authority.
# The project's docs then recorded the result in a table headed "The violent
# veer (captain rulings 2, 4, 5, 6, 7, 8, 9)" in which every row cited a ruling
# number except the one row that mattered, which cited a technical limitation
# and no ruling at all. Seven days later firstmate repeated it to him as his own
# decision. His words: "We never ruled that gravity goes when you veer."
#
# The rule this enforces is deliberately NOT "classify the decision correctly".
# Asked on 2026-08-03 whether the boundary is "an agent never decides anything
# the operator has not decided" or the narrower "an agent never decides anything
# that changes what the thing IS", the captain chose the narrow one:
#   "i dont know, my feeling is the latter becaues it seems easier but it has me
#    worried about slip ups, we can start with it and see how it goes i guess"
# (data/captain-decisions-2026-08-03/agent-invention-boundary.md, 2026-08-03.)
# That rule is provisional and on trial, and it would not have caught the failure
# that prompted it: swapping a gravity switch for sustained force reads as an
# implementation detail and is in fact an identity change, so the case sits
# exactly on the line the rule draws. So the check is attribution instead: a line
# may not claim his authority without something traceable behind it. That holds
# whether the call was a how or a what, and needs no judgment to apply.
#
# What it checks, and only this:
#   1. An AUTHORITY BLOCK is a Markdown heading that claims the captain rulings,
#      decisions, or word, and it runs to the next heading of any level. Only a
#      heading opens one. A bolded caption over a table does not, and neither
#      does a passing mention in prose or in a table cell - each of those was
#      tried and each turned ordinary reference docs into pages of findings.
#      The failure this was built from is headed exactly that way:
#      "### The violent veer (captain rulings 2, 4, 5, 6, 7, 8, 9)".
#   2. Inside that block, every table data row and every list item must carry a
#      RECEIPT: a date (YYYY-MM-DD), a numbered ruling or decision, a quoted
#      span, or a pointer to a captain-decision record. Prose is context, not a
#      claim. Evidence attaches, claims do not inherit. A bullet absorbs the
#      lines below it that are not themselves list items, with or without a
#      blank line between, so a bullet whose quote sits in an indented
#      blockquote below it passes. Every list item is judged on its own text at
#      any depth: a sub-bullet needs its own receipt, cannot borrow the one
#      above it, and cannot lend its own to an unreceipted parent. The failure
#      this was built from is a substitution written beside real rulings, and
#      indenting it one level must not be a way to carry it.
#   3. A bullet that is nothing but a declaration that there is nothing to
#      record - "None recorded for this task." - asserts nothing on his behalf,
#      so it is not judged. That is exactly what the brief scaffold tells
#      firstmate to write when the captain ruled on nothing. A bullet that opens
#      with "none" and then goes on to say something is judged like any other.
#   4. Fenced code blocks (``` or ~~~) are skipped whole. Inside a fence no line
#      is read as a heading, a list item, or a table row, so a shell comment in a
#      sample cannot silently close an authority block and a literal bullet in
#      one cannot be read as a claim.
#   5. "captain" is the whole vocabulary. It also read "owner" once, which
#      flagged 18 rows across one project whose docs simply talk about an owner,
#      and nothing true anywhere.
#
# What it does NOT check, stated plainly because overclaimed provenance is the
# defect this exists to catch: it does not verify that a cited receipt is real,
# says what the row says it says, or belongs to that claim. Reading the record
# is still a person's job. This finds claims with nothing behind them at all,
# which is exactly the shape of the failure above and is worth catching on its
# own.
#
# Measured on 3,693 Markdown files across five real project clones on
# 2026-08-03: 10 findings, all inside the two documents that recorded the
# gravity failure, including its exact row, and none anywhere else.
set -eu

usage() {
  awk '
    NR == 1 { next }
    /^#/ { sub(/^# ?/, ""); print; next }
    { exit }
  ' "$0"
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

[ "$#" -gt 0 ] || { echo "error: no paths given (see --help)" >&2; exit 2; }

FILES=()
for path in "$@"; do
  if [ -d "$path" ]; then
    while IFS= read -r found; do
      [ -n "$found" ] && FILES+=("$found")
    done < <(find "$path" -type f -name '*.md' | LC_ALL=C sort)
  elif [ -f "$path" ]; then
    FILES+=("$path")
  else
    echo "error: not a file or directory: $path" >&2
    exit 2
  fi
done

# A directory holding no Markdown is nothing to judge, not a clean verdict on
# something that was never read.
if [ "${#FILES[@]}" -eq 0 ]; then
  echo "error: no Markdown files found in the given paths" >&2
  exit 2
fi

awk '
  # Claims the captain as the source of a decision. Matched against a
  # lowercased copy of the line, so the patterns stay case-blind without
  # depending on a case-insensitive-match extension.
  # The trailing [^ ]* absorbs a possessive or trailing punctuation without
  # needing to spell every apostrophe byte, and cannot cross a space, so only
  # an adjacent decision word opens a block.
  # No apostrophe may appear anywhere in this awk program: it is a
  # single-quoted shell argument, so one would end the quote and break the
  # whole script.
  function claims_authority(l,   t) {
    t = tolower(l)
    if (t ~ /captain[^ ]* +(ruling|rulings|decision|decisions|decided|ruled|word|order|orders)/) return 1
    if (t ~ /the +captain +(ruled|decided|said|approved|instructed|chose)/) return 1
    if (t ~ /(ruled|decided|approved|instructed|authorized|authorised) +by +the +captain/) return 1
    if (t ~ /per +the +captain/) return 1
    if (t ~ /captain-(approved|ruled|decided)/) return 1
    return 0
  }

  # Something traceable stands behind this text.
  function has_receipt(l,   t) {
    t = tolower(l)
    if (t ~ /[12][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) return 1          # dated
    if (t ~ /(ruling|rulings|decision|decisions)[ ]*#?[ ]*[0-9]/) return 1  # numbered
    if (t ~ /"[^"]+"/) return 1                                            # quoted
    if (index(t, "\342\200\234") > 0) return 1                             # typographic quote
    if (t ~ /captain-decisions/) return 1                                  # record pointer
    return 0
  }

  # A bullet that records that there is nothing to record. The whole bullet has
  # to be that declaration and nothing else: a comma, a colon, or any clause
  # after it means the line went on to say something, and a line that says
  # something under his heading is a claim like any other.
  function declares_absence(l,   t) {
    t = tolower(l)
    return t ~ /^[ \t]*([-*+]|[0-9]+\.)[ \t]+none[a-z ]*[.]?[ \t]*$/
  }

  function is_heading(l)      { return l ~ /^ *#+ +/ }
  function is_blank(l)        { return l ~ /^[ \t]*$/ }
  function is_fence(l)        { return l ~ /^[ \t]*(```|~~~)/ }
  function is_table_row(l)    { return l ~ /^[ \t]*\|/ }
  function is_table_rule(l)   { return l ~ /^[ \t]*\|[-:| \t]+\|?[ \t]*$/ }
  function is_list_item(l)    { return l ~ /^[ \t]*([-*+]|[0-9]+\.)[ \t]+/ }

  # How deeply a line is indented, with a tab counted as four columns so mixed
  # indentation still orders the same way a reader sees it.
  function indent_of(l,   s) {
    s = l
    sub(/[^ \t].*$/, "", s)
    gsub(/\t/, "    ", s)
    return length(s)
  }

  function trim(l) {
    sub(/^[ \t]+/, "", l); sub(/[ \t]+$/, "", l)
    return l
  }

  # A pending list item is only judged once its continuation lines are known,
  # which can be as late as the last line of its file. It therefore carries its
  # own file, line, and opener: by the time it is judged, FILENAME may already
  # name the next file in the argument list.
  function flush_item() {
    blank_pending = 0
    if (item_line == 0) return
    if (!declares_absence(item_first) && !has_receipt(item_text)) report(item_file, item_line, item_first)
    item_line = 0; item_text = ""; item_first = ""; item_indent = 0
  }

  function report(file, line, text) {
    printf "%s:%d: claims the captain\047s authority with no receipt: %s\n", file, line, trim(text)
    findings++
  }

  FNR == 1 {
    flush_item()
    in_block = 0; table_row = 0; in_fence = 0
    item_line = 0; item_text = ""; item_first = ""; item_indent = 0
  }

  {
    line = $0

    # A fenced block is a sample, not structure. Skipping it whole stops a shell
    # comment inside one from closing an authority block, and stops a literal
    # bullet or table row inside one from being read as a claim.
    if (is_fence(line)) { in_fence = !in_fence; next }
    if (in_fence) next

    if (is_heading(line)) {
      flush_item()
      in_block = claims_authority(line)
      table_row = 0
      next
    }

    if (!in_block) next

    # A blank line does not end an open item on its own: an indented quote
    # conventionally sits one blank line below the bullet it belongs to. What
    # comes next decides, so hold the item and judge it on the following line.
    if (is_blank(line)) { if (item_line > 0) blank_pending = 1; table_row = 0; next }

    if (blank_pending) {
      if (indent_of(line) <= item_indent) flush_item()
      blank_pending = 0
    }

    if (is_table_row(line)) {
      flush_item()
      table_row++
      # Row 1 is the header and row 2 its alignment rule; neither is a claim.
      if (table_row > 2 && !is_table_rule(line) && !has_receipt(line)) report(FILENAME, FNR, line)
      next
    }
    table_row = 0

    if (is_list_item(line)) {
      # Every bullet is judged on its own text, however deeply it is nested: a
      # sub-bullet neither borrows the receipt above it nor lends it one.
      flush_item()
      item_line = FNR; item_text = line; item_first = line
      item_file = FILENAME; item_indent = indent_of(line)
      next
    }

    if (item_line > 0) { item_text = item_text " " line; next }   # continuation
  }

  END { flush_item(); if (findings > 0) exit 1 }
' "${FILES[@]}"
