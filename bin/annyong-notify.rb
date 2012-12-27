#!/usr/bin/env ruby
base = __FILE__
while File.symlink?(base)
	base = File.expand_path(File.readlink(base), File.dirnmae(base))
end
path = File.expand_path(File.join(File.dirname(base), "..", "lib"))
$:.unshift path

config_fname = File.expand_path(File.join(path, "..", "config.yml"))
SLEEP_INTERVAL = 62

require 'annyong'

@r = Annyong::RssFeed.new(config_fname)

def ts
	"[#{Time.now.localtime}]"
end

def mail(entry, conf)
	m = Annyong::Mailer.new(conf)
	m.compose_notification(entry)
	if m.mail.subject
		m.send
	else
		puts "#{ts} Skipping notification: #{entry.author} #{entry.verb} on #{entry.number}"
	end
end

def irc(entry, conf)
	@irc ||= Annyong::IrcClient.new(conf)
	@irc.compose_notification(entry)
	@irc.notify
end

loop do

	puts "#{ts} Checking for new activity..."
	@r.fetch
	unless @r.latest.empty?
		@r.latest.each do |entry| 
			mail(entry, config_fname)
			irc(entry, config_fname)
		end
	@r.save
	else
		puts "#{ts} Nothing new, sleeping for #{SLEEP_INTERVAL} seconds..."
	end

	$stdout.flush
	select(nil,nil,nil,SLEEP_INTERVAL)

end


