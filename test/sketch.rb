
require "../lib/annyong.rb"

@r = Annyong::RssFeed.new("config.yml")
@r.fetch

