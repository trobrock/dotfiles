#!/usr/bin/env ruby

require 'csv'
require 'json'

calendars = [
  "Trae Robrock (personal)",
  "trobrock@comfort.ly",
  "trobrock@robrockproperties.com",
  "trae.robrock@huntresslabs.com"
]
agenda = `gcalcli --nocolor agenda #{Time.now.iso8601} --tsv --details conference #{calendars.map { |c| "--calendar \"#{c}\"" }.join(" ")}`

event = nil

CSV.parse(agenda, headers: true, col_sep: "\t") do |row|
  next unless row['start_time']

  event = row
  break
end

time = DateTime.parse("#{event['start_date']} #{event['start_time']}")
data = {
  date: time.strftime("%Y-%m-%d"),
  time: time.strftime("%I:%M %p"),
  title: event['title'],
  conference_url: event['conference_uri']
}

`sketchybar --set $NAME label="#{data[:time]} - #{data[:title]}" click_script="open #{data[:conference_url]}"`
