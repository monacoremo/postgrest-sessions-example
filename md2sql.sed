#!/usr/bin/env -S sed -f

# This `sed` script turns a Markdown file with SQL code blocks into a SQL file.
# The non-SQL lines are commented out in order to maintain the line numbers.
# This can be useful as error messages with line numbers also apply to the
# original file.

# First, we comment out all lines that do not belong to Markdown code blocks
# that start and end with '```'.

/^```/,/^```/ !s/^/-- /

# Explanation:
# * '/^```/,/^```/' matches all ranges of lines that start and end with lines
#   beginning with '```', i.e. the Markdown code blocks in the file.
# * '!' inverts the line selection, so the following command applies to all
#   lines that do not belong to Markdown code blocks.
# * 's/^/-- /' replaces the beginning of the line with '-- ', which comments it
#   out in SQL.

# We also need to comment out the beginnings and ends of the code blocks.

/^```/ s/^/-- /

# This matches all lines beginning with '```' and prepends '-- ' to them
