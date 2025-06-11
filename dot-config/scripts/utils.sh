date_from_string() {
  date_string="$1"
  format="${2:-+%s}"
  date -d "$date_string" "$format" 2> /dev/null || date -j -f "%Y-%m-%d %H:%M" "$date_string" "$format" 2> /dev/null
}

truncate() {
  input="$1"
  length="$2"
  if [[ ${#input} -gt $length ]]; then
    echo "${input:0:length}..."
  else
    echo "$input"
  fi
}
