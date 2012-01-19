#!/usr/bin/env ruby
# coding: utf-8
#
# eboks-backup.rb - download documents stored at www.e-boks.dk
#
# Use Selenium to perform login, so we don't have to figure out how to fool a Java-
# applet. Grab the cookies, and do a straightforward run with Mechanize to grab all
# PDF-files from e-boks.
#
# Only backs up stuff under "Arkivmapper", and doesn't really support nested folders.
#
# FIXME: Doesn't support pagination, since I haven't gotten any folders with that many
# documents yet.
#
# (c) Copyright 2011, Kenneth Vestergaard.

require 'bundler'; Bundler.setup
require 'selenium-webdriver'
require 'mechanize'

## CONFIG

BACKUP_PATH = File.expand_path("~/Documents/Arkiv/e-boks")
SYMLINK = true

##

# Boot Firefox, go to login-page, wait for user to login, and return cookies
def cookies_from_selenium
  driver = Selenium::WebDriver.for :firefox
  driver.navigate.to "https://min.e-boks.dk/logon.aspx?logontype=oces"

  loop do
    break if driver.title == "e-Boks"
    sleep 1
  end

  cookies = driver.manage.all_cookies
  driver.quit
  cookies
end

# Start a Mechanize-session, and add cookies from Selenium
agent = Mechanize.new
page = agent.get('https://min.e-boks.dk/inbox.aspx')

cookies_from_selenium.each do |rawcookie|
  cookie = Mechanize::Cookie.new(rawcookie[:name], rawcookie[:value])
  cookie.domain = rawcookie[:domain]
  cookie.path = rawcookie[:path]
  agent.cookie_jar.add(page.uri, cookie)
end

# Re-fetch page now that the login-cookies have been added
page = agent.get('https://min.e-boks.dk/inbox.aspx')

# Process each folder - the second set of <div class="nodes"> is "Arkivmapper", which is what we're going to backup
page.search('//div[@id="folders"]/div[@class="nodes"][2]//span[@class="node"]/a').each do |folderlink|
  next if folderlink["title"] == "Arkivmapper"

  foldertitle = folderlink["title"]
  folderpath = "#{BACKUP_PATH}/#{foldertitle}"
  folderpath_hidden = "#{folderpath}/.documents"

  puts "\nNavigating to folder '#{foldertitle}'"
  Dir.mkdir folderpath unless Dir.exist? folderpath
  Dir.mkdir folderpath_hidden unless Dir.exist? folderpath_hidden

  folderpage = agent.get("https://min.e-boks.dk/inbox.aspx#{folderlink['href']}")
  folderpage.search('//div[@id="messages"]/ul/li/dl').each do |msg|
    elm = msg.xpath('.//dt/label/input').first
    if elm["name"] != "did"
      $stderr.puts "Error. HTML may have changed, and script needs updating."
      $stderr.puts reason
      exit 1
    end

    did = elm["value"]
    title = msg.xpath('.//dt/label/span').first.content
    sender = msg.xpath('.//dd[@class="content"]/span').first.content
    links = msg.xpath('.//dd[@class="content"]/ul/li/a')
    date = msg.xpath('.//dd[@class="actions"]/span').first.content.split('-').reverse.join('-')

    puts " - found Document ID: #{did} from #{date} (\"#{sender} - #{title}\")"

    links.each do |link|
      doctitle = title
      doctitle = "#{title} (#{link["title"]})" if link["title"] != title # Attachment
      query_args = link["href"].split('?', 2)[1]
      duid = query_args.match(/duid=(\w+)&/).captures.first
      url = "https://download.e-boks.dk/privat/download.aspx?#{query_args.gsub('&', '&amp;')}" # don't ask - the link is pseudo-escaped from e-boks's side
      file = "#{did}-#{duid}.pdf"

      if File.exist? "#{folderpath_hidden}/#{file}"
        puts "   already downloaded, skipping."
        next
      else
        puts "   downloading #{did} (#{doctitle})"
        File.open("#{folderpath_hidden}/#{file}", "w") { |f| f.write agent.get_file(url) }

	doctitle.gsub!(/\//, ':')
        if SYMLINK
          File.symlink(".documents/#{file}", "#{folderpath}/#{date} - #{sender} - #{doctitle}.pdf")
        else
          File.link("#{folderpath_hidden}/#{file}", "#{folderpath}/#{date} - #{sender} - #{doctitle}.pdf")
        end
      end
    end
  end
end
