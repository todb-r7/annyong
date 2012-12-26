require 'simple-rss'
require 'open-uri'
require 'yaml'
require 'nokogiri'

module Annyong

	class RssEntry < Struct.new(
		:id, :title, :verb, :number, :link, :author, 
		:published, :content, :comment_flag
	)
	end

	class RssFeed

		attr_accessor :config
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
				@rss_parsed << this_entry
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

		public

		def fetch
			@rss = SimpleRSS.parse(open(@config["uri"]))
			select_pull_requests
			parse_pull_requests
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
end


