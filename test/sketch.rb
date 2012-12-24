require 'simple-rss'
require 'open-uri'
require 'yaml'

config_file = ARGV[0] || "config.yml"

config = YAML.load(File.read(config_file))
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


@rss = SimpleRSS.parse(open(uri))

owner = config["org"] || config["user"]
repo = config["repo"]
pr_regex = Regexp.new(/pull request #{owner}\x2f#{repo}/)
@pr_entries = @rss.entries.select {|entry| entry.id =~ /:PullRequestEvent/ and entry.title =~ pr_regex}

@pr_entries.each do |entry|
	entry.each_pair do |k,v|
		next if k == :content
		next if k == :updated
		next if k == :"link+alternate"
		next if k.to_s =~ /^media/
		parsed_value = case k
			when :id
				v.split(/\x2f/).last.to_i
			when :link
				URI.parse(v)
			when :author
				v.split.first
			when :title
				matchdata,author,verb,repo,num = v.match(/([^\x20]+) ([^\x20]+) pull request (.*\x2f.*)#([0-9]+)/)
				author,verb,repo,num = matchdata[1,4]
				"Pull Request ##{num} #{verb} by #{author}"
			else
				v
			end
		puts "%-20s%-60s%s" % [k,parsed_value,parsed_value.class.to_s]
	end
	puts ""
end

