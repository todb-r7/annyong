require 'simple-rss'
require 'open-uri'
require 'yaml'
require 'nokogiri'

module Annyong

	class RssEntry < Struct.new(
		:id, :title, :link, :author, 
		:published, :content, :comment_flag
	)
	end

	class RssFeed

		attr_accessor :config, :rss_parsed

		def initialize(config_file)
			@config_file = config_file
			@config = yaml_config(@config_file)
			@owner = config["org"] || config["user"]
			@repo = config["repo"]
			@regex = pull_request_regex
			@rss_parsed = []
		end

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

		def fetch
			@rss = SimpleRSS.parse(open(@config["uri"]))
			@pr_entries = select_pull_requests
			@pr_entries.each do |entry|
				this_entry = RssEntry.new
				this_entry.comment_flag = !!(entry.id =~ /IssueComment/)
				entry.each_pair do |k,v|
					next if k == :updated
					next if k == :"link+alternate"
					next if k.to_s =~ /^media/

					parsed_value = case k
						when :content
							message(v)
						when :id
							v.split(/\x2f/).last.to_i
						when :link
							URI.parse(v)
						when :author
							v.split.first
						when :title
							matchdata,author,verb,repo,num = v.match(/([^\x20]+) (.+) pull request (.*\x2f.*)#([0-9]+)/)
							author,verb,repo,num = matchdata[1,4]
							"Pull Request ##{num} #{this_entry.comment_flag ? "comment" : verb} by #{author}"
						else
							v
					end
					this_entry[k] = parsed_value
				end
				@rss_parsed << this_entry
			end
			@rss_parsed.sort! {|x,y| x.id <=> y.id} # Reverse it, basically
			return @rss_parsed
		end

		def id_list
			if @rss_parsed.first.class == Annyong::RssEntry
				@rss_parsed.map {|x| x.id}
			else
				[]
			end
		end

	end
end


