require 'bundler'
Bundler.setup

require 'simple-rss'
require 'open-uri'
require 'yaml'
require 'nokogiri'
require 'mail'
require 'fileutils'

module Annyong

	class RssEntry < Struct.new(
		:id, :title, :verb, :number, :link, :author, 
		:published, :content, :comment_flag
	)
	end

	class RssFeed

		attr_accessor :config, :id_cache_file
		attr_reader   :rss_parsed

		private

		def parse_html(str)
			ret = str.dup
			ret.gsub!(/&lt;/,"<")
			ret.gsub!(/&gt;/,">")
			ret.gsub!(/&quot;/,"\x22")
			Nokogiri::HTML(ret)
		end

		def message(str)
			doc = parse_html(str)
			ret = nil
			doc.css("blockquote").each do |bq|
				if bq.parent.attributes["class"].value == "message"
					ret = bq.text
				end
				break
			end
			return ret
		end

		def yaml_config(fname)
			config = YAML.load(File.read(fname))
			if config["org"]
				uri = "https://github.com/organizations/%s/%s.private.atom?token=%s" % [
					config["org"],
					config["user"],
					config["token"]
				]
			else
				uri = "https://github.com/%s.private.atom?token=%s" % [
					config["user"],
					config["token"]
				]
			end
			config["uri"] = uri
			config
		end

		def pull_request_regex
			Regexp.new(/pull request #{@owner}\x2f#{@repo}/)
		end

		def select_pull_requests
			@pr_entries = @rss.entries.select do |entry|
				entry.id =~ /:(IssueComment|PullRequest)Event/ and entry.title =~ @regex
			end
		end

		def massage_value(k,v)
			case k
			when :content
				message(v)
			when :id
				v.split(/\x2f/).last.to_i
			when :link
				URI.parse(v)
			when :author
				v.split.first
			when :title
				matchdata = v.match(/[^\x20]+ (.+) pull request .*\x2f.*#([0-9]+)/)
				verb,number = matchdata[1,2]
				verb = "commented" if verb =~ /^comment/
				[verb,number]
			else
				v
			end
		end

		def skip_key?(k)
			k == :updated || k == :"link+alternate" || k.to_s =~ /^media/
		end

		def parse_pull_requests
			@pr_entries.each do |entry|
				this_entry = RssEntry.new
				this_entry.comment_flag = !!(entry.id =~ /IssueComment/)
				entry.each_pair do |k,v|
					next if skip_key?(k)
					this_entry[k] = massage_value(k,v)
					if k == :title
						this_entry[:verb] = this_entry[k][0]
						this_entry[:number] = this_entry[k][1]
					end
				end
				@rss_parsed << this_entry unless ids.include? this_entry.id
			end
			@rss_parsed.sort! {|x,y| x.id <=> y.id} # Reverse it, basically
			return @rss_parsed
		end

		def method_missing(sym, *args, &block)
			if @rss_entry_lists.include? sym
				real_method = sym.to_s.chop.intern
				@rss_parsed.map {|x| x.send real_method}
			else
				super
			end
		end

		def respond_to_missing?(sym, include_private=false)
			@rss_entry_lists.include?(sym) || super
		end

		def id_cache_file
			@id_cache_file ||= "/tmp/annyong_id_cache.txt"
			unless File.readable? @id_cache_file
				File.open(@id_cache_file, "wb") {|f| f.write ""}
			end
			return @id_cache_file
		end

		public

		def cached_ids
			fdata = File.open(id_cache_file, "rb") {|f| f.read f.stat.size}
			fdata.empty? ? [0] : fdata.split.map {|i| i.to_i} 
		end

		def new_ids
			self.ids - cached_ids
		end

		def save
			saved_ids = new_ids
			File.open(id_cache_file, "wb") {|f| f.puts new_ids.join("\n")}
			saved_ids
		end

		def clear_ids
			@rss_parsed = []
		end

		def reset
			@rss_parsed = []
			FileUtils.rm_rf id_cache_file
		end

		def latest
			@rss_parsed.select {|x| new_ids.include? x.id}
		end

		def fetch
			@rss = SimpleRSS.parse(open(@config["uri"]))
			select_pull_requests
			parse_pull_requests
			self.ids
		end

		def initialize(config_file)
			@rss_entry_lists = RssEntry.members.map {|x| (x.to_s + "s").intern}
			@config_file = config_file
			@config = yaml_config(@config_file)
			@owner = config["org"] || config["user"]
			@repo = config["repo"]
			@regex = pull_request_regex
			@rss_parsed = []
		end

	end

	class Mailer

		attr_accessor :mail

		def yaml_config(fname)
			config = YAML.load(File.read(fname))
			@user = config["smtpuser"]
			@pass = config["smtppass"]
			@rcpt = config["rcpt"]
			config
		end

		def config_mail
			user, pass = @user, @pass
			::Mail.defaults do
				delivery_method :smtp, {
					:address => 'smtp.gmail.com',
					:port => '587',
					:user_name => user,
					:password =>  pass,
					:authentication => :plain,
					:enable_starttls_auto => true
				}
			end
		end

		def initialize(config_file)
			@config_file = config_file
			@config = yaml_config(@config_file)
			config_mail
			@mail = ::Mail.new
		end

		def compose_notification(rss_entry)
			unless rss_entry.kind_of? Annyong::RssEntry
				raise ArgumentError, "Expecting an RssEntry"
			end
			subj = case rss_entry.verb
			when "opened" # or reopened
				"New: Pull Request #%d opened by @%s"
			when "reopened"
				"New: Pull Request #%d reopened by @%s"
			when "merged"
				"Complete: Pull Request #%d merged by @%s"
			when "closed"
				"Closed: Pull Request #%d closed by @%s"
			else
				nil
			end

			# If it's not a categorized verb, skip entirely.
			return unless subj

			data = "@%s updated PR#%d" % [rss_entry.author, rss_entry.number]
			data << "\n"
			data << "Title: \x22#{rss_entry.content}\x22\n" 
			data << "\n"
			data << "For more details, visit:\n\n"
			data << rss_entry.link.to_s
			data += "\n\n"

			user,rcpt = @user,@rcpt
			@mail = ::Mail.new do
				from    user
				to      rcpt
				subject subj % [rss_entry.number, rss_entry.author]
				body    data
			end
		end

		def send
			if @mail.kind_of? Mail::Message
				puts "[#{Time.now.localtime}] Sending: #{@mail.subject}"
				@mail.deliver!
			else
				raise RuntimeError, "Nothing to send."
			end	
		end

	end

end


