date_from_string() {
  date_string="$1"
  format="${2:-+%s}"
  date -d "$date_string" "$format" 2> /dev/null || date -j -f "%Y-%m-%d %H:%M" "$date_string" "$format" 2> /dev/null
}

get_end_of_day() {
  local date_input="$1"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    date -j -f "%Y-%m-%d" "$date_input" "+%Y-%m-%dT23:59:59Z"
  else
    date -d "$date_input 23:59:59" +"%Y-%m-%dT%H:%M:%SZ"
  fi
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
