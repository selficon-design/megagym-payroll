#!/bin/bash
# Τρέχει μια εντολή· αν αποτύχει, δείχνει τις τελευταίες γραμμές ως σφάλμα στο GitHub.
out=$("$@" 2>&1); code=$?
echo "$out"
if [ $code -ne 0 ]; then
  echo "$out" | grep -v '^\s*$' | tail -12 | while IFS= read -r l; do echo "::error::${l:0:300}"; done
  exit $code
fi
