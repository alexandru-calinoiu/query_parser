require 'parslet'
require 'pp'

class MyParser < Parslet::Parser
	rule(:term) { match('[a-zA-Z0-9]').repeat(1) }

	rule(:space) { match('\s').repeat(1) }

	rule(:query) { (term >> space.maybe).repeat }

	root(:query)
end

pp MyParser.new.parse('hello world')

begin
	MyParser.new.parse('hello, world')
rescue Parslet::ParseFailed => e
	pp e.parse_failure_cause.ascii_tree
end