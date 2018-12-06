require "csv"
require "octokit"

# default to 90 days
CUTOFF = DateTime.now - 90

# your organization name
ORGANIZATION = "intouchhealth"

User = Struct.new(:type, :username, :full_name, :active, :last_activity, :num_events)
Event = Struct.new(:username, :repository, :date)

UP = "\u2191"
DOWN = "\u2193"

def events
  @events ||= []
end

def users
  @users ||= []
end

def find_user_by_username(username)
  users.detect { |user| user[:username] == username }
end

Octokit.auto_paginate = true
members = Octokit.org_members(ORGANIZATION)
collaborators = Octokit.outside_collaborators(ORGANIZATION, { accept: "org_membership" })
repos = Octokit.org_repos(ORGANIZATION)

puts "Building user list..."
members.each do |member|
  user = Octokit.user(member[:login])
  users << User.new(:member, member[:login], user[:name], false, nil)
end

collaborators.each do |collaborator|
  user = Octokit.user(collaborator[:login])
  users << User.new(:collaborator, collaborator[:login], user[:name], false, nil)
end

puts "Building events list..."
repos.each do |repo|
  repo_events = Octokit.repository_events("#{ORGANIZATION}/#{repo[:name]}")
  repo_events.each { |event| events << Event.new(event[:actor][:login], repo[:name], event[:created_at]) }
end

puts "Processing events..."
events.each do |event|
  user = find_user_by_username(event[:username])
  next if user.nil?

  user[:num_events] = 0 if user[:num_events].nil?
  user[:num_events] = user[:num_events] + 1

  if user[:last_activity].nil?
    user[:last_activity] = event[:date]
  else
    user[:last_activity] = event[:date] if event[:date] >= user[:last_activity]
  end
end

puts "Processing user activity..."
users.each do |user|
  next if user[:last_activity].nil?

  user[:active] = true if user[:last_activity].to_datetime >= CUTOFF
end

puts "Comparing to previous report..."
`mv report.csv report_old.csv`
old_report = []
old_report = CSV.read("report_old.csv") if File.file?("report_old.csv")
old_report_hash = {}
if old_report.length > 1
  # Remove the header of the CSV file.
  old_report.delete_at 0

  old_report.each do |item|
    old_report_hash[item[1]] = item
  end
end

puts "Generating CSV..."
CSV.open("report.csv", "wb") do |csv|
  csv << ["type", "username", "full name", "active", "last_activity", "num_events", "change from last report"]
  users.each do |user|
    difference = "0"
    user[:num_events] = 0 if user[:num_events].nil?

    difference = (user[:num_events].to_i - old_report_hash[user[:username]][5].to_i).to_s unless old_report_hash[user[:username]].nil?
    difference += " #{UP.encode('utf-8')}" if difference.to_i > 0
    difference += " #{DOWN.encode('utf-8')}" if difference.to_i < 0

    csv << [user[:type], user[:username], user[:full_name], user[:active], user[:last_activity], user[:num_events], difference]
  end
end

